package com.rork.catchwordsandroid.data

import android.graphics.Bitmap
import android.graphics.PointF
import android.graphics.RectF
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * On-device subject lifting — the Android counterpart of iOS `VNGenerateForegroundInstanceMaskRequest`:
 * ML Kit subject segmentation (multi-subject, on device, free, offline once Play services has the module).
 * One request per photo, reused for every object in it (`InstanceMasks`).
 */
object CutoutService {
    private const val TAG = "CutoutService"

    private val segmenter by lazy {
        SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder()
                .enableMultipleSubjects(
                    SubjectSegmenterOptions.SubjectResultOptions.Builder().enableConfidenceMask().enableSubjectBitmap().build(),
                )
                .build(),
        )
    }

    /** Starts the module download / initialisation early (the first photo should not wait for it). */
    fun warmUp() {
        runCatching { segmenter.initTask }
    }

    /** Nil when no subject was found (or the module is not ready on this device). */
    suspend fun instanceMasks(source: Bitmap): InstanceMasks? = withContext(Dispatchers.Default) {
        val photo = ImageTools.software(ImageTools.resized(source, 1600))
        val result = suspendCancellableCoroutine<com.google.mlkit.vision.segmentation.subject.SubjectSegmentationResult?> { cont ->
            segmenter.process(InputImage.fromBitmap(photo, 0))
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { e ->
                    Log.w(TAG, "segmentation failed: ${e.javaClass.simpleName}")
                    cont.resume(null)
                }
        } ?: return@withContext null
        val subjects = result.subjects.filter { it.width > 2 && it.height > 2 }
        if (subjects.isEmpty()) return@withContext null
        InstanceMasks.build(photo, subjects.map { s ->
            val mask = s.confidenceMask
            val conf = FloatArray(s.width * s.height)
            mask?.rewind()
            mask?.get(conf, 0, min(conf.size, mask.remaining()))
            InstanceMasks.Subject(s.startX, s.startY, s.width, s.height, conf, s.bitmap)
        })
    }

    /** One subject near `point` (0–1, top-left origin), cropped to it; nil = nothing to lift. */
    suspend fun liftSubject(source: Bitmap, point: PointF?): Bitmap? {
        val masks = instanceMasks(source) ?: return null
        val label = point?.let { p -> masks.instances(p).firstOrNull()?.label } ?: masks.largestLabel() ?: return null
        return withContext(Dispatchers.Default) { masks.cut(label)?.image }
    }
}

/**
 * The result of one segmentation: a label mask (≤512 px, 0 = background), each subject's cut-out and its box
 * (0–1 of the photo), the tags' anchors and the scan's outlines.
 */
class InstanceMasks private constructor(
    val photoWidth: Int,
    val photoHeight: Int,
    private val subjects: List<Subject>,
    val mask: ByteArray,
    val maskWidth: Int,
    val maskHeight: Int,
) {
    class Subject(val x: Int, val y: Int, val w: Int, val h: Int, val conf: FloatArray, val bitmap: Bitmap?)

    /** The subject on transparency, cropped to `box` (0–1 of the photo). */
    class Cut(val image: Bitmap, val box: RectF)

    data class InstanceHit(val label: Int, val distance: Int)

    private val cache = mutableMapOf<Int, Cut>()
    private var anchorCache: Map<Int, PointF>? = null

    val labels: List<Int> get() = subjects.indices.map { it + 1 }

    fun largestLabel(): Int? {
        val counts = IntArray(256)
        mask.forEach { b -> val l = b.toInt() and 0xFF; if (l != 0) counts[l]++ }
        return (1..255).filter { counts[it] > 0 }.maxByOrNull { counts[it] }
    }

    /** Every label within ~8% of `p`, nearest first (0 = the point lies on it). Same as iOS `rankedInstances`. */
    fun instances(p: PointF): List<InstanceHit> {
        val w = maskWidth
        val h = maskHeight
        val x = (p.x * w).toInt().coerceIn(0, w - 1)
        val y = (p.y * h).toInt().coerceIn(0, h - 1)
        fun label(px: Int, py: Int) = mask[py * w + px].toInt() and 0xFF
        val best = mutableMapOf<Int, Int>()
        val under = label(x, y)
        if (under != 0) best[under] = 0
        val reach = max(4, (max(w, h) * 0.08).toInt())
        val step = max(1, reach / 16)
        var py = max(0, y - reach)
        while (py <= min(h - 1, y + reach)) {
            var px = max(0, x - reach)
            while (px <= min(w - 1, x + reach)) {
                val l = label(px, py)
                if (l != 0) {
                    val d = (px - x) * (px - x) + (py - y) * (py - y)
                    if (d < (best[l] ?: Int.MAX_VALUE)) best[l] = d
                }
                px += step
            }
            py += step
        }
        return best.map { InstanceHit(it.key, it.value) }.sortedWith(compareBy({ it.distance }, { it.label }))
    }

    @Synchronized
    fun anchors(): Map<Int, PointF> {
        anchorCache?.let { return it }
        val found = CatchAnchor.anchors(mask, maskWidth, maskHeight)
        anchorCache = found
        return found
    }

    fun outlines(limit: Int = CatchObject.MAX_OBJECTS): List<CatchOutline> =
        CatchOutlineTracer.outlines(mask, maskWidth, maskHeight, limit)

    fun prerenderCuts(limit: Int = 6) {
        labels.take(limit).forEach { cut(it) }
    }

    @Synchronized
    fun cut(label: Int): Cut? {
        cache[label]?.let { return it }
        val s = subjects.getOrNull(label - 1) ?: return null
        val bmp = s.bitmap ?: return null
        // Tight alpha bounds inside the subject's box.
        val pixels = IntArray(bmp.width * bmp.height)
        bmp.getPixels(pixels, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        var x0 = bmp.width
        var y0 = bmp.height
        var x1 = -1
        var y1 = -1
        for (yy in 0 until bmp.height) {
            val row = yy * bmp.width
            for (xx in 0 until bmp.width) {
                if ((pixels[row + xx] ushr 24) > 8) {
                    if (xx < x0) x0 = xx
                    if (xx > x1) x1 = xx
                    if (yy < y0) y0 = yy
                    if (yy > y1) y1 = yy
                }
            }
        }
        if (x1 < x0 || y1 < y0) return null
        val cropped = Bitmap.createBitmap(bmp, x0, y0, x1 - x0 + 1, y1 - y0 + 1)
        val W = photoWidth.toFloat()
        val H = photoHeight.toFloat()
        val c = Cut(cropped, RectF((s.x + x0) / W, (s.y + y0) / H, (s.x + x1 + 1) / W, (s.y + y1 + 1) / H))
        cache[label] = c
        return c
    }

    companion object {
        /** Builds the label mask (≤512 px on its long side): each pixel goes to the most confident subject above 0.5. */
        fun build(photo: Bitmap, subjects: List<Subject>, maxSide: Int = 512): InstanceMasks {
            val W = photo.width
            val H = photo.height
            val step = max(1, ceil(max(W, H).toDouble() / maxSide).toInt())
            val mw = (W + step - 1) / step
            val mh = (H + step - 1) / step
            val mask = ByteArray(mw * mh)
            val best = FloatArray(mw * mh)
            subjects.take(255).forEachIndexed { i, s ->
                val label = (i + 1).toByte()
                for (my in 0 until mh) {
                    val py = my * step - s.y
                    if (py < 0 || py >= s.h) continue
                    for (mx in 0 until mw) {
                        val px = mx * step - s.x
                        if (px < 0 || px >= s.w) continue
                        val c = s.conf[py * s.w + px]
                        val k = my * mw + mx
                        if (c > 0.5f && c > best[k]) {
                            best[k] = c
                            mask[k] = label
                        }
                    }
                }
            }
            return InstanceMasks(W, H, subjects.take(255), mask, mw, mh)
        }
    }
}

/**
 * One object in the photo = the candidates sharing `group` (up to 3 words), its AI point, its box, where its tag sits
 * (`anchor`, deep inside its segmented subject) and its cut-out. Port of iOS `CatchObject`.
 */
data class CatchObject(
    val id: Int,
    val words: List<Candidate>,
    val point: PointF,
    val box: RectF,
    val anchor: PointF,
    val cut: Bitmap?,
    val instance: Int?,
) {
    companion object {
        const val MAX_OBJECTS = 4
        const val MAX_WORDS = 3

        fun groups(items: List<Candidate>): List<List<Candidate>> {
            val order = mutableListOf<String>()
            val buckets = mutableMapOf<String, MutableList<Candidate>>()
            items.forEachIndexed { i, c ->
                val key = c.group?.let { "g$it" } ?: "solo$i"
                if (key !in buckets) order += key
                buckets.getOrPut(key) { mutableListOf() }.add(c)
            }
            return order.take(MAX_OBJECTS).mapNotNull { k -> buckets[k]?.take(MAX_WORDS)?.takeIf { it.isNotEmpty() } }
        }

        fun build(candidates: List<Candidate>, masks: InstanceMasks?, photoW: Int, photoH: Int): List<CatchObject> {
            val list = groups(candidates)
            val points = list.map { w ->
                PointF((w[0].point.first / 1000.0).toFloat().coerceIn(0f, 1f), (w[0].point.second / 1000.0).toFloat().coerceIn(0f, 1f))
            }
            val labels = masks?.let { m -> assignInstances(points.map { m.instances(it) }) } ?: List(points.size) { null }
            val inside = masks?.anchors() ?: emptyMap()
            return list.mapIndexed { i, words ->
                val p = points[i]
                val deep = labels[i]?.let { inside[it] }
                val cut = labels[i]?.let { masks?.cut(it) }
                if (cut != null) {
                    CatchObject(i, words, p, cut.box, deep ?: PointF(cut.box.centerX(), cut.box.centerY()), cut.image, labels[i])
                } else {
                    CatchObject(i, words, p, fallbackBox(p, photoW, photoH), deep ?: p, null, labels[i])
                }
            }
        }

        /** Closest (object, instance) pairs first; never the same instance twice. */
        fun assignInstances(ranked: List<List<InstanceMasks.InstanceHit>>): List<Int?> {
            val pairs = ranked.flatMapIndexed { i, hits -> hits.map { i to it } }
                .sortedWith(compareBy({ it.second.distance }, { it.first }))
            val out = MutableList<Int?>(ranked.size) { null }
            val taken = mutableSetOf<Int>()
            for ((o, h) in pairs) {
                if (out[o] == null && h.label !in taken) {
                    out[o] = h.label
                    taken += h.label
                }
            }
            return out
        }

        fun fallbackBox(p: PointF, w: Int, h: Int): RectF {
            val side = 0.36f * min(w, h)
            val bw = min(1f, side / max(w, 1))
            val bh = min(1f, side / max(h, 1))
            val x = (p.x - bw / 2).coerceIn(0f, 1f - bw)
            val y = (p.y - bh / 2).coerceIn(0f, 1f - bh)
            return RectF(x, y, x + bw, y + bh)
        }
    }
}

/** Where a thing's name tag sits on its subject: deep inside its largest piece, nearest its centroid. Port of iOS `CatchAnchor`. */
object CatchAnchor {
    private const val DEPTH = 0.6

    fun anchors(mask: ByteArray, w: Int, h: Int): Map<Int, PointF> {
        if (w <= 0 || h <= 0 || mask.size < w * h) return emptyMap()
        val minX = IntArray(256) { w }
        val minY = IntArray(256) { h }
        val maxX = IntArray(256) { -1 }
        val maxY = IntArray(256) { -1 }
        for (y in 0 until h) for (x in 0 until w) {
            val l = mask[y * w + x].toInt() and 0xFF
            if (l == 0) continue
            if (x < minX[l]) minX[l] = x
            if (x > maxX[l]) maxX[l] = x
            if (y < minY[l]) minY[l] = y
            if (y > maxY[l]) maxY[l] = y
        }
        val out = mutableMapOf<Int, PointF>()
        for (l in 1 until 256) {
            if (maxX[l] < 0) continue
            anchor(mask, w, h, l.toByte(), minX[l], minY[l], maxX[l], maxY[l])?.let { out[l] = it }
        }
        return out
    }

    private fun anchor(mask: ByteArray, w: Int, h: Int, label: Byte, x0: Int, y0: Int, x1: Int, y1: Int): PointF? {
        val gw = x1 - x0 + 3
        val gh = y1 - y0 + 3
        val d = IntArray(gw * gh)
        val far = Int.MAX_VALUE / 4
        for (y in y0..y1) for (x in x0..x1) if (mask[y * w + x] == label) d[(y - y0 + 1) * gw + (x - x0 + 1)] = far
        val around = intArrayOf(-gw - 1, -gw, -gw + 1, -1, 1, gw - 1, gw, gw + 1)
        val piece = IntArray(gw * gh)
        val stack = ArrayDeque<Int>()
        var id = 0
        var kept = 0
        var keptSize = 0
        for (start in d.indices) {
            if (d[start] == 0 || piece[start] != 0) continue
            id++
            piece[start] = id
            stack.addLast(start)
            var size = 0
            while (stack.isNotEmpty()) {
                val j = stack.removeLast()
                size++
                for (o in around) {
                    val k = j + o
                    if (d[k] != 0 && piece[k] == 0) {
                        piece[k] = id
                        stack.addLast(k)
                    }
                }
            }
            if (size > keptSize) {
                keptSize = size
                kept = id
            }
        }
        if (keptSize == 0) return null
        for (y in 1 until gh - 1) for (x in 1 until gw - 1) {
            val i = y * gw + x
            if (d[i] == 0) continue
            d[i] = minOf(d[i], d[i - 1] + 3, d[i - gw] + 3, minOf(d[i - gw - 1] + 4, d[i - gw + 1] + 4))
        }
        for (y in gh - 2 downTo 1) for (x in gw - 2 downTo 1) {
            val i = y * gw + x
            if (d[i] == 0) continue
            d[i] = minOf(d[i], d[i + 1] + 3, d[i + gw] + 3, minOf(d[i + gw + 1] + 4, d[i + gw - 1] + 4))
        }
        var deepest = 0
        var sx = 0.0
        var sy = 0.0
        for (i in d.indices) if (piece[i] == kept) {
            deepest = max(deepest, d[i])
            sx += i % gw
            sy += i / gw
        }
        val enough = deepest * DEPTH
        val cx = sx / keptSize
        val cy = sy / keptSize
        var best = -1
        var bestD = Double.MAX_VALUE
        for (i in d.indices) if (piece[i] == kept && d[i] >= enough) {
            val dx = i % gw - cx
            val dy = i / gw - cy
            val q = dx * dx + dy * dy
            if (q < bestD) {
                bestD = q
                best = i
            }
        }
        if (best < 0) return null
        val px = best % gw - 1 + x0
        val py = best / gw - 1 + y0
        return PointF((px + 0.5f) / w, (py + 0.5f) / h)
    }
}

/** One thing's smoothed outline (0–1 of the photo, clockwise), for the catch scan. */
data class CatchOutline(val label: Int, val area: Double, val points: List<PointF>)

/** Pixel-edge tracing + Douglas–Peucker + Chaikin ×3 + moving average — port of iOS `CatchOutlineTracer`. */
object CatchOutlineTracer {
    fun outlines(mask: ByteArray, width: Int, height: Int, limit: Int = 4, minArea: Double = 0.012): List<CatchOutline> {
        if (width <= 0 || height <= 0 || mask.size < width * height) return emptyList()
        val counts = IntArray(256)
        for (i in 0 until width * height) {
            val l = mask[i].toInt() and 0xFF
            if (l != 0) counts[l]++
        }
        val total = (width * height).toDouble()
        val order = (1 until 256).filter { counts[it] > 0 }.sortedWith(compareBy({ -counts[it] }, { it }))
        val out = mutableListOf<CatchOutline>()
        for (label in order) {
            if (out.size >= limit) break
            val share = counts[label] / total
            if (share < minArea) continue
            val ring = boundary(mask, width, height, label.toByte()) ?: continue
            var pts = simplify(ring, 0.75f)
            if (pts.size < 3) continue
            pts = chaikin(pts, 3)
            pts = movingAverage(pts, 5, 2)
            out += CatchOutline(label, share, pts.map { PointF(it.x / width, it.y / height) })
        }
        return out
    }

    private fun boundary(mask: ByteArray, w: Int, h: Int, label: Byte): List<PointF>? {
        val piece = IntArray(w * h)
        val stack = ArrayDeque<Int>()
        var bestStart = -1
        var bestSize = 0
        var bestId = 0
        var id = 0
        for (i in 0 until w * h) {
            if (mask[i] != label || piece[i] != 0) continue
            id++
            piece[i] = id
            stack.addLast(i)
            var size = 0
            while (stack.isNotEmpty()) {
                val j = stack.removeLast()
                size++
                val jx = j % w
                val jy = j / w
                for (dy in -1..1) {
                    val ny = jy + dy
                    if (ny < 0 || ny >= h) continue
                    for (dx in -1..1) {
                        if (dx == 0 && dy == 0) continue
                        val nx = jx + dx
                        if (nx < 0 || nx >= w) continue
                        val k = ny * w + nx
                        if (mask[k] == label && piece[k] == 0) {
                            piece[k] = id
                            stack.addLast(k)
                        }
                    }
                }
            }
            if (size > bestSize) {
                bestSize = size
                bestStart = i
                bestId = id
            }
        }
        if (bestStart < 0) return null
        val sx = bestStart % w
        val sy = bestStart / w
        fun inside(x: Int, y: Int) = x in 0 until w && y in 0 until h && piece[y * w + x] == bestId
        val stepX = intArrayOf(1, 0, -1, 0)
        val stepY = intArrayOf(0, 1, 0, -1)
        fun sides(x: Int, y: Int, d: Int): Pair<Boolean, Boolean> = when (d) {
            0 -> inside(x, y) to inside(x, y - 1)
            1 -> inside(x - 1, y) to inside(x, y)
            2 -> inside(x - 1, y - 1) to inside(x - 1, y)
            else -> inside(x, y - 1) to inside(x - 1, y - 1)
        }
        var x = sx
        var y = sy
        var d = 0
        val corners = mutableListOf(PointF(sx.toFloat(), sy.toFloat()))
        repeat(4 * (w + 1) * (h + 1)) {
            x += stepX[d]
            y += stepY[d]
            var next = -1
            for (turn in intArrayOf(3, 0, 1)) {
                val o = (d + turn) % 4
                val (r, l) = sides(x, y, o)
                if (r && !l) {
                    next = o
                    break
                }
            }
            if (next < 0) return null
            if (x == sx && y == sy && next == 0) return corners
            if (next != d) corners += PointF(x.toFloat(), y.toFloat())
            d = next
        }
        return null
    }

    private fun simplify(pts: List<PointF>, eps: Float): List<PointF> {
        if (pts.size <= 3) return pts
        var far = 0
        var farD = -1f
        pts.forEachIndexed { i, p ->
            val dd = (p.x - pts[0].x) * (p.x - pts[0].x) + (p.y - pts[0].y) * (p.y - pts[0].y)
            if (dd > farD) {
                farD = dd
                far = i
            }
        }
        val a = dp(pts.subList(0, far + 1), eps)
        val b = dp(pts.subList(far, pts.size) + pts[0], eps)
        return a.dropLast(1) + b.dropLast(1)
    }

    private fun dp(pts: List<PointF>, eps: Float): List<PointF> {
        if (pts.size <= 2) return pts
        val keep = BooleanArray(pts.size)
        keep[0] = true
        keep[pts.size - 1] = true
        val stack = ArrayDeque<Pair<Int, Int>>()
        stack.addLast(0 to pts.size - 1)
        while (stack.isNotEmpty()) {
            val (i, j) = stack.removeLast()
            if (j <= i + 1) continue
            var bestD = -1f
            var bestK = -1
            for (k in i + 1 until j) {
                val dd = dist(pts[k], pts[i], pts[j])
                if (dd > bestD) {
                    bestD = dd
                    bestK = k
                }
            }
            if (bestD > eps && bestK >= 0) {
                keep[bestK] = true
                stack.addLast(i to bestK)
                stack.addLast(bestK to j)
            }
        }
        return pts.filterIndexed { i, _ -> keep[i] }
    }

    private fun dist(p: PointF, a: PointF, b: PointF): Float {
        val vx = b.x - a.x
        val vy = b.y - a.y
        val len = hypot(vx, vy)
        if (len < 1e-9f) return hypot(p.x - a.x, p.y - a.y)
        return abs(vy * p.x - vx * p.y + b.x * a.y - b.y * a.x) / len
    }

    private fun chaikin(pts: List<PointF>, iterations: Int): List<PointF> {
        var cur = pts
        repeat(iterations) {
            val n = cur.size
            if (n <= 2) return cur
            val out = ArrayList<PointF>(2 * n)
            for (i in 0 until n) {
                val p = cur[i]
                val q = cur[(i + 1) % n]
                out += PointF(0.75f * p.x + 0.25f * q.x, 0.75f * p.y + 0.25f * q.y)
                out += PointF(0.25f * p.x + 0.75f * q.x, 0.25f * p.y + 0.75f * q.y)
            }
            cur = out
        }
        return cur
    }

    private fun movingAverage(pts: List<PointF>, radius: Int, passes: Int): List<PointF> {
        val n = pts.size
        if (n <= 2 * radius + 1) return pts
        var cur = pts
        val span = (2 * radius + 1).toFloat()
        repeat(passes) {
            cur = List(n) { i ->
                var sx = 0f
                var sy = 0f
                for (d in -radius..radius) {
                    val p = cur[(i + d + n) % n]
                    sx += p.x
                    sy += p.y
                }
                PointF(sx / span, sy / span)
            }
        }
        return cur
    }
}
