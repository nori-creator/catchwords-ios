package com.rork.catchwordsandroid.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.location.Geocoder
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.resume

/** web `checkOwnedWord` → a word already in the dex: catching it again is a re-encounter, never a duplicate. */
data class OwnedWord(
    val stickerId: String,
    val wordId: String,
    val headword: String,
    val meaning: String,
    val readingZhuyin: String?,
    val pinyin: String?,
    val cutoutUrl: String?,
    val encounterCount: Int,
    val takenAtMs: Long?,
    val locationName: String?,
) {
    companion object {
        fun from(o: JsonObject): OwnedWord? {
            val id = o.str("sticker_id") ?: o.str("stickerId") ?: return null
            return OwnedWord(
                stickerId = id,
                wordId = o.str("word_id") ?: o.str("wordId") ?: "",
                headword = o.str("headword") ?: "",
                meaning = o.str("meaning_ja") ?: o.str("meaningJa") ?: "",
                readingZhuyin = o.str("reading_zhuyin") ?: o.str("readingZhuyin"),
                pinyin = o.str("pinyin"),
                cutoutUrl = o.str("cutout_url") ?: o.str("cutoutUrl"),
                encounterCount = o.int("encounter_count") ?: o.int("encounterCount") ?: 1,
                takenAtMs = parseDate(o.str("taken_at") ?: o.str("takenAt")),
                locationName = o.str("location_name") ?: o.str("locationName"),
            )
        }

        fun fromSticker(s: Sticker): OwnedWord = OwnedWord(
            s.id, s.wordId, s.word?.headword.orEmpty(), s.word?.meaning.orEmpty(), s.word?.readingZhuyin, s.word?.pinyin,
            null, 1, s.takenAtMs, s.locationName,
        )
    }
}

/** Where a catch happened (web: lat / lng / location_name). */
data class Place(val lat: Double, val lng: Double, val name: String?)

/** Current position (when allowed) and its place name, in the display language. */
class LocationService(private val context: Context) {
    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    suspend fun currentPlace(): Place? {
        if (!hasPermission()) return null
        val loc = withTimeoutOrNull(8_000) {
            suspendCancellableCoroutine<android.location.Location?> { cont ->
                val cts = CancellationTokenSource()
                cont.invokeOnCancellation { cts.cancel() }
                runCatching {
                    LocationServices.getFusedLocationProviderClient(context)
                        .getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cts.token)
                        .addOnSuccessListener { cont.resume(it) }
                        .addOnFailureListener { cont.resume(null) }
                }.onFailure { cont.resume(null) }
            }
        } ?: return null
        return Place(loc.latitude, loc.longitude, placeName(loc.latitude, loc.longitude))
    }

    @Suppress("DEPRECATION")
    suspend fun placeName(lat: Double, lng: Double): String? = withContext(Dispatchers.IO) {
        if (!Geocoder.isPresent()) return@withContext null
        val locale = when (L10n.current) { "ja" -> Locale.JAPAN; "zh-TW" -> Locale.TAIWAN; else -> Locale.US }
        val list = withTimeoutOrNull(6_000) {
            if (Build.VERSION.SDK_INT >= 33) {
                suspendCancellableCoroutine<List<android.location.Address>?> { cont ->
                    Geocoder(context, locale).getFromLocation(lat, lng, 1) { cont.resume(it) }
                }
            } else {
                runCatching { Geocoder(context, locale).getFromLocation(lat, lng, 1) }.getOrNull()
            }
        }
        val a = list?.firstOrNull() ?: return@withContext null
        listOfNotNull(a.subLocality ?: a.locality ?: a.subAdminArea, a.thoroughfare ?: a.featureName)
            .distinct().joinToString(" ").ifBlank { a.adminArea }
    }
}

/** One photo kept in 「解析待ち」 until its analysis has been used (iOS PendingQueue). */
@Serializable
data class PendingCatch(val id: String, val file: String, val reason: String, val createdAt: Long)

/** Photos waiting for analysis, kept on the device (files + a small JSON index). */
class PendingQueue(context: Context) {
    private val dir = File(context.filesDir, "pending").apply { mkdirs() }
    private val index = File(dir, "index.json")
    private val _items = MutableStateFlow(read())
    val items: StateFlow<List<PendingCatch>> = _items.asStateFlow()

    private fun read(): List<PendingCatch> = runCatching {
        AppJson.decodeFromString(ListSerializer(PendingCatch.serializer()), index.readText())
    }.getOrDefault(emptyList()).filter { File(dir, it.file).exists() }

    private fun write(list: List<PendingCatch>) {
        _items.value = list
        runCatching { index.writeText(AppJson.encodeToString(ListSerializer(PendingCatch.serializer()), list)) }
    }

    suspend fun add(image: Bitmap, reason: String): String? = withContext(Dispatchers.IO) {
        val id = UUID.randomUUID().toString()
        val name = "$id.jpg"
        runCatching {
            File(dir, name).outputStream().use { ImageTools.resized(image, 1600).compress(Bitmap.CompressFormat.JPEG, 85, it) }
            synchronized(this@PendingQueue) { write(listOf(PendingCatch(id, name, reason, System.currentTimeMillis())) + _items.value.take(19)) }
            id
        }.getOrNull()
    }

    suspend fun updateReason(id: String, reason: String) = withContext(Dispatchers.IO) {
        synchronized(this@PendingQueue) { write(_items.value.map { if (it.id == id) it.copy(reason = reason) else it }) }
    }

    suspend fun remove(id: String) = withContext(Dispatchers.IO) {
        synchronized(this@PendingQueue) {
            _items.value.firstOrNull { it.id == id }?.let { File(dir, it.file).delete() }
            write(_items.value.filter { it.id != id })
        }
    }

    suspend fun image(item: PendingCatch): Bitmap? = withContext(Dispatchers.IO) {
        runCatching { BitmapFactory.decodeFile(File(dir, item.file).path) }.getOrNull()
    }

    fun thumbnailFile(item: PendingCatch): File = File(dir, item.file)
}
