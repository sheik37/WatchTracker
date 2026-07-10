package com.example.myapplication

import android.app.Application
import com.example.myapplication.data.DataContainer

class WatchTrackerApp : Application() {
    lateinit var container: DataContainer

    override fun onCreate() {
        super.onCreate()
        container = DataContainer(this)
    }
}
