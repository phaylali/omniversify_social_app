package com.omniversify.omniversify_social_app

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.MediaButtonReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val widgetChannel = "omniversify/music_widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playPause" -> {
                        sendMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                        result.success(null)
                    }
                    "next" -> {
                        sendMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
                        result.success(null)
                    }
                    "previous" -> {
                        sendMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetAction(intent)
    }

    private fun handleWidgetAction(intent: Intent?) {
        val action = intent?.getStringExtra("widget_action") ?: return
        intent.removeExtra("widget_action")
        val keyCode = when (action) {
            "play_pause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return
        }
        // Defer until the Flutter engine + media session are up.
        window.decorView.postDelayed({ sendMediaKey(keyCode) }, 800)
    }

    private fun sendMediaKey(keyCode: Int) {
        val down = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val intent = Intent(this, MediaButtonReceiver::class.java).apply {
            action = Intent.ACTION_MEDIA_BUTTON
            putExtra(Intent.EXTRA_KEY_EVENT, down)
        }
        sendBroadcast(intent)
    }
}
