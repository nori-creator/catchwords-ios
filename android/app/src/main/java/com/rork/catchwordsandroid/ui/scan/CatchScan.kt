package com.rork.catchwordsandroid.ui.scan

import android.graphics.BlurMaskFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Shader
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import com.rork.catchwordsandroid.data.CatchObject
import com.rork.catchwordsandroid.data.CatchOutline
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

// The catch scan, v10 — port of iOS CatchScan.swift: a bracket slides onto each thing and clicks, a pen of light
// draws its outline in one stroke (slower where it turns), hops to the next; the pen speeds up once the names are in;
// tags come up once their thing has a name and a closed outline. All geometry here is in dp.

object CatchScanSpec {
    const val bracketIn = 0.12
    const val appear = 0.26
    const val move = 0.54
    const val hop = 0.26
    const val fadeOut = 0.3
    const val catchWindow = 0.5
    const val ramp = 0.15
    const val kMax = 4.0
    const val tagLead = 0.14
    const val tagGap = 0.13
    const val tagAfterClose = 0.1
    const val patrolDelay = 0.3
    const val patrolIn = 0.3
    const val patrolOut = 0.25
    const val penOut = 0.25
    const val outlineWait = 0.6
    const val px = 1f / 2.75f
    const val penRadius = 34 * px
    const val smallRadius = 20 * px
    const val patrolSpeed = 1350 * px
    const val spacing = 4 * px
    const val edge = 6 * px
    const val hopRise = 160 * px
    const val pad = 14f
    const val margin = 10f
    const val bracketLine = 3f
    const val bracketRadius = 12f
    const val bracketArm = 19f
    fun duration(r: Double): Double = min(1.0, max(0.6, 0.43 + 0.53 * r))
}

/** CSS cubic-bezier, solved for y at x. */
class CubicBezier(private val x1: Double, private val y1: Double, private val x2: Double, private val y2: Double) {
    private fun bx(t: Double) = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t
    private fun by(t: Double) = 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t
    operator fun invoke(x: Double): Double {
        if (x <= 0) return 0.0
        if (x >= 1) return 1.0
        var lo = 0.0
        var hi = 1.0
        repeat(30) {
            val m = (lo + hi) / 2
            if (bx(m) < x) lo = m else hi = m
        }
        return by((lo + hi) / 2)
    }
}

object ScanEase {
    private val bracketCurve = CubicBezier(0.3, 1.3, 0.5, 1.0)
    private val easeInOut = CubicBezier(0.42, 0.0, 0.58, 1.0)
    fun bracket(u: Double): Float = bracketCurve(u).toFloat()
    fun outCubic(u: Double) = 1 - (1 - u).pow(3)
    fun inOutCubic(u: Double) = if (u < 0.5) 4 * u * u * u else 1 - (-2 * u + 2).pow(3) / 2
    fun inOutSine(u: Double) = -(cos(PI * u.coerceIn(0.0, 1.0)) - 1) / 2
    fun easeInOut(u: Double) = easeInOut.invoke(u)
}

class CatchScanTimeline(val durations: List<Double>, ready: Double, val bracketIn: Double = CatchScanSpec.bracketIn) {
    val lock: List<Double>
    var catchFrom: Double? = null
        private set
    private var k = 1.0

    init {
        var t = max(bracketIn + CatchScanSpec.appear, ready) + CatchScanSpec.move
        val l = mutableListOf<Double>()
        for (d in durations) {
            l += t
            t += d + CatchScanSpec.hop
        }
        lock = l
    }

    fun moveStart(r: Int) = lock[r] - CatchScanSpec.move
    fun close(r: Int) = lock[r] + durations[r]
    val drawEnd: Double get() = if (durations.isEmpty()) bracketIn + CatchScanSpec.appear else close(durations.size - 1)

    fun startCatchUp(t: Double) {
        if (catchFrom != null) return
        catchFrom = t
        val s = CatchScanSpec
        val left = drawEnd - t
        k = if (left <= s.catchWindow) 1.0 else min(s.kMax, 1 + (left - s.catchWindow) / (s.catchWindow - s.ramp / 2))
    }

    private fun extra(d: Double): Double {
        val r = CatchScanSpec.ramp
        if (d <= r) {
            val u = d / r
            return r * (u * u * u - u * u * u * u / 2)
        }
        return r / 2 + (d - r)
    }

    fun tau(t: Double): Double {
        val c = catchFrom ?: return t
        if (k == 1.0 || t <= c) return t
        return t + (k - 1) * extra(t - c)
    }

    fun real(x: Double): Double {
        val c = catchFrom ?: return x
        if (k == 1.0 || x <= c) return x
        var lo = c
        var hi = x
        repeat(40) {
            val m = (lo + hi) / 2
            if (tau(m) < x) lo = m else hi = m
        }
        return hi
    }

    fun found(names: Double) = if (durations.isEmpty()) names else max(names, real(close(0)))

    fun tag(k: Int, rank: Int?, names: Double): Double {
        val s = CatchScanSpec
        val base = found(names) + s.tagLead + s.tagGap * k
        if (rank == null || rank < 0 || rank >= durations.size) return base
        return max(base, real(close(rank)) + s.tagAfterClose)
    }
}

class CatchScanShape private constructor(
    val label: Int,
    val pts: List<Offset>,
    val edge: FloatArray,
    val pace: DoubleArray,
    val duration: Double,
    val box: Rect,
) {
    fun head(lock: Double, tau: Double): Pair<Double, Offset> {
        val n = pts.size
        if (tau <= lock) return 0.0 to pts[0]
        if (tau >= lock + duration) return n.toDouble() to pts[0]
        fun td(i: Int) = lock + duration * pace[i]
        var lo = 0
        var hi = n - 1
        while (lo < hi) {
            val m = (lo + hi + 1) / 2
            if (td(m) <= tau) lo = m else hi = m - 1
        }
        val t0 = if (lo == 0 && td(0) > tau) lock else td(lo)
        val t1 = td(min(n - 1, lo + 1))
        val f = if (t1 > t0) ((tau - t0) / (t1 - t0)).coerceIn(0.0, 1.0) else 0.0
        val p = pts[lo]
        val q = pts[(lo + 1) % n]
        return (lo + f) to Offset(p.x + (q.x - p.x) * f.toFloat(), p.y + (q.y - p.y) * f.toFloat())
    }

    companion object {
        fun make(outline: CatchOutline, fill: Rect, stage: Size, diagonal: Float): CatchScanShape? {
            val s = CatchScanSpec
            var p = outline.points.map { Offset(fill.left + it.x * fill.width, fill.top + it.y * fill.height) }
            if (p.size < 3) return null
            var area = 0f
            for (i in p.indices) {
                val a = p[i]
                val b = p[(i + 1) % p.size]
                area += a.x * b.y - b.x * a.y
            }
            if (area < 0) p = p.reversed()
            val top = p.indices.minByOrNull { p[it].y } ?: 0
            p = p.subList(top, p.size) + p.subList(0, top)
            val pts = resample(p, s.spacing)
            val n = pts.size
            if (n < 8) return null
            val edge = FloatArray(n) { minOf(pts[it].x, stage.width - pts[it].x, min(pts[it].y, stage.height - pts[it].y)) }
            val turn = DoubleArray(n)
            for (i in 0 until n) {
                val a = pts[(i - 3 + n) % n]
                val q = pts[i]
                val b = pts[(i + 3) % n]
                val a1 = atan2((q.y - a.y).toDouble(), (q.x - a.x).toDouble())
                val a2 = atan2((b.y - q.y).toDouble(), (b.x - q.x).toDouble())
                var d = abs(a2 - a1)
                if (d > PI) d = 2 * PI - d
                turn[i] = d
            }
            val cum = DoubleArray(n)
            var acc = 0.0
            var length = 0f
            for (i in 0 until n) {
                var sum = 0.0
                for (d in -4..4) sum += turn[(i + d + n) % n]
                val atEdge = edge[i] < s.edge
                acc += (1 + 2.6 * sum / 9) * (if (atEdge) 0.25 else 1.0)
                cum[i] = acc
                val b = pts[(i + 1) % n]
                length += hypot(b.x - pts[i].x, b.y - pts[i].y) * (if (atEdge) 0.25f else 1f)
            }
            val tot = max(acc, 1e-9)
            val x0 = pts.minOf { it.x }
            val y0 = pts.minOf { it.y }
            val x1 = pts.maxOf { it.x }
            val y1 = pts.maxOf { it.y }
            return CatchScanShape(
                outline.label, pts, edge,
                DoubleArray(n) { acos(1 - 2 * min(1.0, cum[it] / tot)) / PI },
                s.duration((length / max(diagonal, 1f)).toDouble()),
                Rect(x0, y0, x1, y1),
            )
        }

        fun resample(pts: List<Offset>, step: Float): List<Offset> {
            if (pts.size <= 1 || step <= 0) return pts
            val out = mutableListOf(pts[0])
            var carry = 0f
            val n = pts.size
            for (i in 0 until n) {
                var a = pts[i]
                val b = pts[(i + 1) % n]
                var seg = hypot(b.x - a.x, b.y - a.y)
                while (seg > 0 && carry + seg >= step) {
                    val f = (step - carry) / seg
                    a = Offset(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)
                    out += a
                    seg = hypot(b.x - a.x, b.y - a.y)
                    carry = 0f
                }
                carry += seg
            }
            if (out.size > 2 && hypot(out.last().x - out[0].x, out.last().y - out[0].y) < step / 2) out.removeAt(out.size - 1)
            return out
        }
    }
}

class CatchScanPlan(outlines: List<CatchOutline>, val stage: Size, val fill: Rect, val readyAt: Double) {
    class PatrolLeg(val shape: Int?, val pts: List<Offset>, val cum: FloatArray, val start: Float)

    val shapes: List<CatchScanShape>
    val timeline: CatchScanTimeline
    val full: Rect = Rect(22f, stage.height * 0.12f, 22f + max(40f, stage.width - 44f), stage.height * 0.88f)
    val boxes: List<Rect>
    val patrol: List<PatrolLeg>
    val patrolLength: Float

    init {
        val s = CatchScanSpec
        val diagonal = hypot(stage.width, stage.height)
        shapes = outlines.mapNotNull { CatchScanShape.make(it, fill, stage, diagonal) }
        timeline = CatchScanTimeline(shapes.map { it.duration }, readyAt)
        boxes = shapes.map { sh ->
            val b = sh.box.inflate(s.pad)
            val x0 = max(s.margin, b.left)
            val y0 = max(s.margin, b.top)
            val x1 = min(stage.width - s.margin, b.right)
            val y1 = min(stage.height - s.margin, b.bottom)
            Rect(x0, y0, x0 + max(24f, x1 - x0), y0 + max(24f, y1 - y0))
        }
        val legs = mutableListOf<PatrolLeg>()
        var total = 0f
        shapes.forEachIndexed { r, sh ->
            val ring = sh.pts + sh.pts[0]
            val cum = FloatArray(ring.size)
            for (i in 1 until ring.size) {
                val d = hypot(ring[i].x - ring[i - 1].x, ring[i].y - ring[i - 1].y)
                cum[i] = cum[i - 1] + d * (if (sh.edge[i - 1] < s.edge) 0.25f else 1f)
            }
            legs += PatrolLeg(r, ring, cum, total)
            total += cum.last()
            val a = sh.pts[0]
            val b = shapes[(r + 1) % shapes.size].pts[0]
            val c = hopControl(a, b)
            val air = (0..40).map { bez2(a, c, b, it / 40.0) }
            val acum = FloatArray(air.size)
            for (i in 1 until air.size) acum[i] = acum[i - 1] + hypot(air[i].x - air[i - 1].x, air[i].y - air[i - 1].y)
            legs += PatrolLeg(null, air, acum, total)
            total += acum.last()
        }
        patrol = legs
        patrolLength = total
    }

    fun patrolPoint(distance: Float): Triple<Int, Int, Offset>? {
        if (patrolLength <= 0 || patrol.isEmpty()) return null
        var pos = distance % patrolLength
        if (pos < 0) pos += patrolLength
        var li = patrol.size - 1
        for (i in patrol.indices) if (pos < patrol[i].start + patrol[i].cum.last()) { li = i; break }
        val leg = patrol[li]
        val local = pos - leg.start
        var lo = 0
        var hi = leg.cum.size - 1
        while (lo < hi - 1) {
            val m = (lo + hi) / 2
            if (leg.cum[m] <= local) lo = m else hi = m
        }
        val span = max(leg.cum[hi] - leg.cum[lo], 1e-6f)
        val f = ((local - leg.cum[lo]) / span).coerceIn(0f, 1f)
        val p = leg.pts[lo]
        val q = leg.pts[hi]
        return Triple(li, lo, Offset(p.x + (q.x - p.x) * f, p.y + (q.y - p.y) * f))
    }

    companion object {
        fun fillRect(photo: Size, size: Size): Rect {
            if (photo.width <= 0 || photo.height <= 0) return Rect(Offset.Zero, size)
            val scale = max(size.width / photo.width, size.height / photo.height)
            val w = photo.width * scale
            val h = photo.height * scale
            return Rect((size.width - w) / 2, (size.height - h) / 2, (size.width + w) / 2, (size.height + h) / 2)
        }

        fun hopControl(a: Offset, b: Offset) = Offset((a.x + b.x) / 2, min(a.y, b.y) - CatchScanSpec.hopRise)

        fun bez2(a: Offset, c: Offset, b: Offset, u: Double): Offset {
            val uf = u.toFloat()
            val v = 1 - uf
            return Offset(v * v * a.x + 2 * v * uf * c.x + uf * uf * b.x, v * v * a.y + 2 * v * uf * c.y + uf * uf * b.y)
        }
    }
}

/**
 * One photo's scan, kept by the capture view model for the run. The words screen starts it (`begin`), tells it where
 * the photo sits (`layout`), steps it every frame (sounds + tags), and draws it on a Canvas.
 */
class CatchScanSession {
    enum class Phase { SCANNING, NAMING, DONE }

    var revealed: Set<Int> by mutableStateOf(emptySet())
        private set
    var phase: Phase by mutableStateOf(Phase.SCANNING)
        private set
    var settled: Boolean by mutableStateOf(false)
        private set

    /** Sound / haptic hooks set by the screen. */
    var onScanStart: () -> Unit = {}
    var onLock: () -> Unit = {}
    var onFound: () -> Unit = {}
    var onPop: () -> Unit = {}

    private var started: Double? = null
    private var outlines: List<CatchOutline>? = null
    private var outlinesAt: Double? = null
    private var namesAt: Double? = null
    private var objects: List<CatchObject> = emptyList()
    private var plan: CatchScanPlan? = null
    private var stage: Size? = null
    private var fill: Rect? = null
    private val fired = mutableSetOf<String>()
    private val rankOf = mutableMapOf<Int, Int>()
    private var unnamed: Set<Int> = emptySet()

    fun begin(now: Double) {
        if (started == null) started = now
    }

    fun layout(stage: Size, fill: Rect) {
        if (stage.width <= 1 || stage.height <= 1) return
        this.stage = stage
        this.fill = fill
    }

    fun setOutlines(list: List<CatchOutline>, at: Double) {
        if (outlines != null) return
        outlines = list
        outlinesAt = at
    }

    fun setNames(list: List<CatchObject>, at: Double) {
        if (namesAt != null) return
        objects = list
        namesAt = at
    }

    /** Names in and nothing to scan (a restored or typed run): show the tags at once. */
    fun revealAll() {
        revealed = objects.map { it.id }.toSet()
        phase = Phase.DONE
        settled = true
    }

    private fun rel(at: Double?): Double? {
        val s = started ?: return null
        return max(0.0, (at ?: return null) - s)
    }

    private class Moments(val names: Double, val found: Double, val tags: Map<Int, Double>)

    private fun moments(): Moments? {
        val names = rel(namesAt) ?: return null
        val plan = plan ?: return null
        val tl = plan.timeline
        val found = tl.found(names)
        val tags = objects.mapIndexed { k, o -> o.id to tl.tag(k, rankOf[o.id], names) }.toMap()
        return Moments(names, found, tags)
    }

    fun step(now: Double) {
        val s = started ?: return
        val t = now - s
        buildPlan(t)
        val plan = plan ?: return
        val names = rel(namesAt)
        if (names != null && plan.timeline.catchFrom == null && plan.shapes.isNotEmpty()) {
            plan.timeline.startCatchUp(max(names, plan.readyAt))
        }
        val tl = plan.timeline
        fire("in", tl.bracketIn, t, onScanStart)
        for (r in plan.shapes.indices) fire("lock$r", tl.real(tl.lock[r]), t, onLock)
        var lastTag = 0.0
        moments()?.let { m ->
            fire("found", m.found, t, onFound)
            val add = mutableSetOf<Int>()
            for (o in objects) {
                val due = m.tags[o.id] ?: continue
                lastTag = max(lastTag, due)
                if (t >= due && o.id !in revealed) {
                    add += o.id
                    if (t - due < 0.25) onPop()
                }
            }
            if (add.isNotEmpty()) revealed = revealed + add
        }
        val drawEnd = if (plan.shapes.isEmpty()) 0.0 else tl.real(tl.drawEnd)
        val drawing = plan.shapes.isEmpty() || t < drawEnd
        val next = when {
            names != null && revealed.size >= objects.size -> Phase.DONE
            drawing || names != null -> Phase.SCANNING
            else -> Phase.NAMING
        }
        if (next != phase) phase = next
        if (next == Phase.DONE && !settled && t >= max(drawEnd + CatchScanSpec.penOut, lastTag) + 0.6) settled = true
    }

    /** Settled and no named outline left to pulse: the canvas can stop redrawing. */
    fun idle(): Boolean {
        if (!settled) return false
        val plan = plan ?: return true
        return plan.shapes.indices.all { it in unnamed }
    }

    private fun fire(id: String, due: Double, t: Double, action: () -> Unit) {
        if (t < due || id in fired) return
        fired += id
        if (t - due < 0.25) action()
    }

    private fun buildPlan(t: Double) {
        if (plan == null) {
            val st = stage
            val fl = fill
            if (st != null && fl != null) {
                val ol = outlines
                val names = rel(namesAt)
                if (ol != null) {
                    plan = CatchScanPlan(ol, st, fl, rel(outlinesAt) ?: t)
                } else if (names != null && t >= names + CatchScanSpec.outlineWait) {
                    plan = CatchScanPlan(emptyList(), st, fl, t)
                }
            }
        }
        val plan = plan ?: return
        if (namesAt != null && rankOf.isEmpty() && unnamed.isEmpty()) {
            val named = mutableSetOf<Int>()
            for (o in objects) {
                val label = o.instance ?: continue
                val r = plan.shapes.indexOfFirst { it.label == label }
                if (r >= 0) {
                    rankOf[o.id] = r
                    named += r
                }
            }
            unnamed = plan.shapes.indices.toSet() - named
            if (unnamed.isEmpty()) unnamed = setOf(-1)
        }
    }

    // region Drawing (DrawScope in px; plan in dp, scaled by `density`)

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val addMode = PorterDuffXfermode(PorterDuff.Mode.ADD)
    private val screenMode = PorterDuffXfermode(PorterDuff.Mode.SCREEN)

    fun draw(scope: DrawScope, photo: Size, now: Double) {
        val s = started ?: return
        val t = now - s
        val d = scope.density
        val size = Size(scope.size.width / d, scope.size.height / d)
        val m = moments()
        val names = m?.names
        scope.drawIntoCanvas { canvas ->
            val c = canvas.nativeCanvas
            val on = ScanEase.outCubic((t / 0.5).coerceIn(0.0, 1.0))
            val off = names?.let { ScanEase.inOutCubic(((t - it - 0.25) / 0.6).coerceIn(0.0, 1.0)) } ?: 0.0
            val dim = 0.2 * on * (1 - off)
            if (dim > 0.003) c.drawColor(android.graphics.Color.argb((dim * 255).toInt(), 0, 0, 0))
            c.save()
            c.scale(d, d)
            val plan = plan
            if (plan == null) {
                drawBracket(c, fullRect(size), bracketAppear(t), false, breath(t))
                c.restore()
                return@drawIntoCanvas
            }
            val fillNow = CatchScanPlan.fillRect(photo, size)
            val moved = abs(fillNow.width - plan.fill.width) > 0.5f || abs(fillNow.left - plan.fill.left) > 0.5f || abs(fillNow.top - plan.fill.top) > 0.5f
            if (plan.fill.width > 0 && moved) {
                val k = fillNow.width / plan.fill.width
                c.translate(fillNow.left, fillNow.top)
                c.scale(k, k)
                c.translate(-plan.fill.left, -plan.fill.top)
            }
            val tl = plan.timeline
            val tau = tl.tau(t)
            drawOutlines(c, plan, t, tau, m?.found)
            drawTrails(c, plan, t, tau, names)
            val fadeFrom = if (plan.shapes.isEmpty()) (m?.found ?: Double.POSITIVE_INFINITY) else tl.real(tl.drawEnd)
            val alpha = bracketAppear(tau) * (1 - ((t - fadeFrom) / CatchScanSpec.fadeOut).coerceIn(0.0, 1.0))
            if (alpha > 0.003) {
                var r = -1
                for (i in plan.shapes.indices) if (tau >= tl.moveStart(i)) r = i
                val to = if (r < 0) plan.full else plan.boxes[r]
                val from = if (r <= 0) plan.full else plan.boxes[r - 1]
                val u = if (r < 0) 1f else ScanEase.bracket(((tau - tl.moveStart(r)) / CatchScanSpec.move).coerceIn(0.0, 1.0))
                val rect = Rect(
                    from.left + (to.left - from.left) * u, from.top + (to.top - from.top) * u,
                    from.right + (to.right - from.right) * u, from.bottom + (to.bottom - from.bottom) * u,
                )
                val locked = r >= 0 && tau >= tl.lock[r]
                var squash = if (plan.shapes.isEmpty()) breath(t) else 1f
                if (locked) {
                    val v = ((tau - tl.lock[r]) / 0.26).coerceIn(0.0, 1.0)
                    squash = (1 - 0.06 * (1 - abs(1 - 2 * v))).toFloat()
                }
                drawBracket(c, rect, alpha, locked, squash)
            }
            penAt(plan, t, tau)?.let { pen -> glowDot(c, pen.first, CatchScanSpec.penRadius, pen.second * edgeFade(pen.first, plan.stage)) }
            val pa = patrolAlpha(plan, t, names)
            if (pa > 0) {
                plan.patrolPoint(((t - patrolStart(plan)) * CatchScanSpec.patrolSpeed).toFloat())?.let { p ->
                    glowDot(c, p.third, CatchScanSpec.smallRadius, 0.8 * pa * edgeFade(p.third, plan.stage))
                }
            }
            c.restore()
        }
    }

    private fun fullRect(size: Size) = Rect(22f, size.height * 0.12f, 22f + max(40f, size.width - 44f), size.height * 0.88f)

    private fun bracketAppear(tau: Double): Double {
        val u = (tau - CatchScanSpec.bracketIn) / CatchScanSpec.appear
        return if (u <= 0) 0.0 else ScanEase.bracket(min(1.0, u)).toDouble().coerceIn(0.0, 1.0)
    }

    private fun breath(t: Double): Float {
        val s = sin(PI * max(0.0, t - CatchScanSpec.bracketIn) / 1.2)
        return (1 - 0.02 * s * s).toFloat()
    }

    private fun patrolStart(plan: CatchScanPlan) = plan.timeline.real(plan.timeline.drawEnd) + CatchScanSpec.patrolDelay

    private fun patrolAlpha(plan: CatchScanPlan, t: Double, names: Double?): Double {
        if (plan.shapes.isEmpty()) return 0.0
        val p0 = patrolStart(plan)
        val n = names ?: Double.POSITIVE_INFINITY
        if (n <= p0) return 0.0
        return ((t - p0) / CatchScanSpec.patrolIn).coerceIn(0.0, 1.0) * (1 - ((t - n) / CatchScanSpec.patrolOut).coerceIn(0.0, 1.0))
    }

    private class Pen(val at: Offset, val alpha: Double, val hop: Triple<Offset, Offset, Double>?)

    private fun penFull(plan: CatchScanPlan, t: Double, tau: Double): Pen? {
        val tl = plan.timeline
        for (r in plan.shapes.indices) {
            val lock = tl.lock[r]
            val close = tl.close(r)
            if (tau >= lock && tau < close) return Pen(plan.shapes[r].head(lock, tau).second, 1.0, null)
            if (r < plan.shapes.size - 1 && tau >= close && tau < tl.lock[r + 1]) {
                val a = plan.shapes[r].pts[0]
                val b = plan.shapes[r + 1].pts[0]
                val u = ScanEase.inOutSine((tau - close) / (tl.lock[r + 1] - close))
                return Pen(CatchScanPlan.bez2(a, CatchScanPlan.hopControl(a, b), b, u), 0.55, Triple(a, b, u))
            }
        }
        val last = plan.shapes.lastOrNull() ?: return null
        val end = tl.real(tl.drawEnd)
        if (t >= end && t < end + CatchScanSpec.penOut) return Pen(last.pts[0], 1 - (t - end) / CatchScanSpec.penOut, null)
        return null
    }

    private fun penAt(plan: CatchScanPlan, t: Double, tau: Double): Pair<Offset, Double>? = penFull(plan, t, tau)?.let { it.at to it.alpha }

    private fun edgeFade(p: Offset, stage: Size): Double {
        val d = minOf(p.x, stage.width - p.x, min(p.y, stage.height - p.y))
        return ((d - 4 * CatchScanSpec.px) / (36 * CatchScanSpec.px)).toDouble().coerceIn(0.0, 1.0)
    }

    private fun outlineAlpha(r: Int, t: Double, found: Double?): Double {
        if (found == null || t <= found) return 1.0
        val p = ((t - found) % 2) / 2
        var a = if (p < 0.5) 1 - 0.5 * ScanEase.easeInOut(p * 2) else 0.5 + 0.5 * ScanEase.easeInOut(p * 2 - 1)
        if (r in unnamed) a *= 1 - min(1.0, (t - found) / 0.4)
        return a
    }

    private fun drawnPath(sh: CatchScanShape, h: Double): android.graphics.Path {
        val path = android.graphics.Path()
        var down = false
        val n = sh.pts.size
        val last = min(n, h.toInt())
        fun put(q: Offset, e: Float) {
            if (e < CatchScanSpec.edge) {
                down = false
                return
            }
            if (down) path.lineTo(q.x, q.y) else {
                path.moveTo(q.x, q.y)
                down = true
            }
        }
        for (i in 0..last) put(sh.pts[i % n], sh.edge[i % n])
        if (h < n) {
            val f = (h - last).toFloat()
            val p = sh.pts[last % n]
            val q = sh.pts[(last + 1) % n]
            put(Offset(p.x + (q.x - p.x) * f, p.y + (q.y - p.y) * f), min(sh.edge[last % n], sh.edge[(last + 1) % n]))
        }
        return path
    }

    private fun strokeOutline(c: android.graphics.Canvas, path: android.graphics.Path, box: Rect, alpha: Double) {
        linePaint.shader = null
        linePaint.xfermode = screenMode
        for ((blur, a) in listOf(2.5f to 0.65, 8f to 0.6)) {
            linePaint.strokeWidth = 3.5f
            linePaint.maskFilter = BlurMaskFilter(blur, BlurMaskFilter.Blur.NORMAL)
            linePaint.color = android.graphics.Color.argb((a * alpha * 255).toInt().coerceIn(0, 255), 120, 190, 255)
            c.drawPath(path, linePaint)
        }
        linePaint.xfermode = null
        // Soft drop glows under the core line.
        linePaint.maskFilter = BlurMaskFilter(10f, BlurMaskFilter.Blur.NORMAL)
        linePaint.strokeWidth = 4f
        linePaint.color = android.graphics.Color.argb((0.45 * alpha * 255).toInt().coerceIn(0, 255), 40, 120, 255)
        c.drawPath(path, linePaint)
        linePaint.maskFilter = BlurMaskFilter(3f, BlurMaskFilter.Blur.NORMAL)
        linePaint.strokeWidth = 3f
        linePaint.color = android.graphics.Color.argb((0.9 * alpha * 255).toInt().coerceIn(0, 255), 140, 200, 255)
        c.drawPath(path, linePaint)
        linePaint.maskFilter = null
        linePaint.strokeWidth = 1.75f
        linePaint.color = android.graphics.Color.WHITE
        linePaint.alpha = (alpha * 255).toInt().coerceIn(0, 255)
        linePaint.shader = LinearGradient(
            box.left, box.top, box.right, box.bottom,
            intArrayOf(0xFFBFE8FF.toInt(), 0xFF9CC8FF.toInt(), 0xFFCFE3FF.toInt()), null, Shader.TileMode.CLAMP,
        )
        c.drawPath(path, linePaint)
        linePaint.shader = null
    }

    private fun drawOutlines(c: android.graphics.Canvas, plan: CatchScanPlan, t: Double, tau: Double, found: Double?) {
        plan.shapes.forEachIndexed { r, sh ->
            if (tau < plan.timeline.lock[r]) return@forEachIndexed
            val a = outlineAlpha(r, t, found)
            if (a <= 0.005) return@forEachIndexed
            val h = sh.head(plan.timeline.lock[r], tau).first
            strokeOutline(c, drawnPath(sh, h), sh.box, a)
        }
    }

    private fun drawTrails(c: android.graphics.Canvas, plan: CatchScanPlan, t: Double, tau: Double, names: Double?) {
        class Seg(val p: Offset, val q: Offset, val a: Double, val w: Float)
        val segs = mutableListOf<Seg>()
        val tl = plan.timeline
        plan.shapes.forEachIndexed { r, sh ->
            val lock = tl.lock[r]
            if (tau < lock || tau > tl.close(r) + 0.4) return@forEachIndexed
            val n = sh.pts.size
            val h = min(n - 1, sh.head(lock, tau).first.toInt())
            for (i in max(0, h - 60) until max(0, h)) {
                val a = 0.75 * exp(-(tau - (lock + sh.duration * sh.pace[i])) / 0.14)
                segs += Seg(sh.pts[i], sh.pts[i + 1], a, 2.4f)
            }
        }
        penFull(plan, t, tau)?.hop?.let { hop ->
            val ctl = CatchScanPlan.hopControl(hop.first, hop.second)
            val m = (hop.third * 40).toInt()
            for (i in max(0, m - 14) until m) {
                segs += Seg(
                    CatchScanPlan.bez2(hop.first, ctl, hop.second, i / 40.0),
                    CatchScanPlan.bez2(hop.first, ctl, hop.second, (i + 1) / 40.0),
                    0.3 * exp(-(m - i) / 6.0), 1.6f,
                )
            }
        }
        val pa = patrolAlpha(plan, t, names)
        if (pa > 0) {
            plan.patrolPoint(((t - patrolStart(plan)) * CatchScanSpec.patrolSpeed).toFloat())?.let { p ->
                val leg = plan.patrol[p.first]
                val si = leg.shape
                if (si != null) {
                    val ring = plan.shapes[si].pts
                    val n = ring.size
                    val j = p.second + n
                    fun at(i: Int) = ring[((i % n) + n) % n]
                    for (i in j - 30 until j) segs += Seg(at(i), at(i + 1), 0.55 * pa * exp(-(j - i) / 9.0), 2f)
                } else {
                    val m = p.second
                    for (i in max(0, m - 10) until m) segs += Seg(leg.pts[i], leg.pts[i + 1], 0.25 * pa * exp(-(m - i) / 5.0), 1.4f)
                }
            }
        }
        if (segs.isEmpty()) return
        linePaint.shader = null
        linePaint.xfermode = addMode
        for (blurred in listOf(true, false)) {
            linePaint.maskFilter = if (blurred) BlurMaskFilter(1.8f, BlurMaskFilter.Blur.NORMAL) else null
            for (sg in segs) {
                val al = sg.a * min(edgeFade(sg.p, plan.stage), edgeFade(sg.q, plan.stage))
                if (al < 0.01) continue
                linePaint.strokeWidth = sg.w
                linePaint.color = android.graphics.Color.argb((min(1.0, al) * 255).toInt(), 200, 232, 255)
                c.drawLine(sg.p.x, sg.p.y, sg.q.x, sg.q.y, linePaint)
            }
        }
        linePaint.maskFilter = null
        linePaint.xfermode = null
    }

    private fun drawBracket(c: android.graphics.Canvas, rect: Rect, alpha: Double, locked: Boolean, squash: Float) {
        if (alpha <= 0.003) return
        val s = CatchScanSpec
        val d = -s.bracketLine / 2
        val r = s.bracketRadius - s.bracketLine / 2
        val arm = s.bracketArm
        val path = android.graphics.Path()
        listOf(
            floatArrayOf(rect.left, rect.top, 1f, 1f), floatArrayOf(rect.right, rect.top, -1f, 1f),
            floatArrayOf(rect.left, rect.bottom, 1f, -1f), floatArrayOf(rect.right, rect.bottom, -1f, -1f),
        ).forEach { (x, y, sx, sy) ->
            path.moveTo(x + sx * d, y + sy * arm)
            path.lineTo(x + sx * d, y + sy * (d + r))
            path.quadTo(x + sx * d, y + sy * d, x + sx * (d + r), y + sy * d)
            path.lineTo(x + sx * arm, y + sy * d)
        }
        c.save()
        c.scale(squash, squash, rect.center.x, rect.center.y)
        linePaint.shader = null
        linePaint.strokeCap = Paint.Cap.BUTT
        linePaint.strokeWidth = s.bracketLine
        linePaint.maskFilter = BlurMaskFilter(6f, BlurMaskFilter.Blur.NORMAL)
        linePaint.color = android.graphics.Color.argb((0.9 * alpha * 255).toInt(), 100, 224, 255)
        c.drawPath(path, linePaint)
        linePaint.maskFilter = null
        linePaint.color = if (locked) android.graphics.Color.argb((alpha * 255).toInt(), 0x6C, 0xC8, 0xFF) else android.graphics.Color.argb((alpha * 255).toInt(), 255, 255, 255)
        c.drawPath(path, linePaint)
        linePaint.strokeCap = Paint.Cap.ROUND
        c.restore()
    }

    private fun glowDot(c: android.graphics.Canvas, p: Offset, r: Float, a: Double) {
        if (a <= 0.01) return
        val al = a.coerceIn(0.0, 1.0)
        fillPaint.xfermode = addMode
        fillPaint.shader = RadialGradient(
            p.x, p.y, r,
            intArrayOf(
                android.graphics.Color.argb((al * 255).toInt(), 255, 255, 255),
                android.graphics.Color.argb((0.6 * al * 255).toInt(), 160, 215, 255),
                android.graphics.Color.argb(0, 160, 215, 255),
            ),
            floatArrayOf(0f, 0.28f, 1f), Shader.TileMode.CLAMP,
        )
        c.drawCircle(p.x, p.y, r, fillPaint)
        fillPaint.shader = null
        fillPaint.xfermode = null
    }

    // endregion
}
