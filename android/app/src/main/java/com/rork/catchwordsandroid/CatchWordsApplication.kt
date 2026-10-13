package com.rork.catchwordsandroid

import android.app.Application
import com.rork.catchwordsandroid.data.AppGraph

class CatchWordsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppGraph.init(this)
    }
}
