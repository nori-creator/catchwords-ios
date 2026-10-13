package com.rork.catchwordsandroid.data

import android.content.Context

/** App-wide singletons (one Supabase session, one dex) shared by every screen's ViewModel. */
object AppGraph {
    lateinit var client: SupabaseClient
        private set
    lateinit var api: NativeApi
        private set
    lateinit var consent: AiConsentStore
        private set
    lateinit var profile: ProfileRepository
        private set
    lateinit var dex: DexRepository
        private set
    lateinit var speech: Speech
        private set
    lateinit var prefs: android.content.SharedPreferences
        private set
    lateinit var pending: PendingQueue
        private set
    lateinit var location: LocationService
        private set

    lateinit var appContext: Context
        private set

    fun init(context: Context) {
        appContext = context.applicationContext
        L10n.init(context)
        prefs = context.getSharedPreferences("cw.prefs", Context.MODE_PRIVATE)
        client = SupabaseClient(context)
        api = NativeApi(client) { consent }
        consent = AiConsentStore(context, client) { api }
        profile = ProfileRepository(client)
        dex = DexRepository(client, api, profile)
        speech = Speech(context)
        pending = PendingQueue(context)
        location = LocationService(context)
    }

    /** 設定 › 発音表記: "zhuyin" (default) or "pinyin". */
    var readingStyle: String
        get() = prefs.getString("reading.style", "zhuyin") ?: "zhuyin"
        set(value) = prefs.edit().putString("reading.style", value).apply()

    /** 設定 › 自撮りも撮る (iOS selfie.mode): after the photo, the front camera asks for one with the thing. */
    var selfieMode: Boolean
        get() = prefs.getBoolean("selfie.mode", false)
        set(value) = prefs.edit().putBoolean("selfie.mode", value).apply()

    /** 設定 › 場所を記録: the catch keeps where it happened (asks for location permission). */
    var recordPlace: Boolean
        get() = prefs.getBoolean("place.record", true)
        set(value) = prefs.edit().putBoolean("place.record", value).apply()

    var soundsOn: Boolean
        get() = prefs.getBoolean("sounds.on", true)
        set(value) = prefs.edit().putBoolean("sounds.on", value).apply()
}
