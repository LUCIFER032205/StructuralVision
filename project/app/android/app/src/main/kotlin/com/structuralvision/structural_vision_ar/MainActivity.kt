package com.structuralvision.structural_vision_ar

import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Physical device rotation from the accelerometer, snapped to 0/90/180/270.
    // The camera plugin tags photos from the *screen* rotation, which never
    // changes with auto-rotate off, so landscape shots came out tagged portrait.
    private var rotation = 0
    private val listener by lazy {
        object : OrientationEventListener(this) {
            override fun onOrientationChanged(o: Int) {
                // Flat (pointing at floor/ceiling) reports UNKNOWN: keep the last value.
                if (o != ORIENTATION_UNKNOWN) rotation = ((o + 45) / 90 * 90) % 360
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "structural_vision/orientation")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceRotation") result.success(rotation) else result.notImplemented()
            }
    }

    override fun onResume() {
        super.onResume()
        if (listener.canDetectOrientation()) listener.enable()
    }

    override fun onPause() {
        listener.disable()
        super.onPause()
    }
}
