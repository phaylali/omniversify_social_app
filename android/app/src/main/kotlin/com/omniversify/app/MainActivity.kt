package com.omniversify.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import android.webkit.MimeTypeMap
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.MediaButtonReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : AudioServiceActivity() {
    private val widgetChannel = "omniversify/music_widget"
    private val actionChannel = "omniversify/audio_actions"

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
        setupAudioActionChannel(flutterEngine)
    }

    // ── Ringtone / file actions (triggered from Dart on demand only) ──────

    private fun setupAudioActionChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, actionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canWriteSettings" ->
                        result.success(Settings.System.canWrite(this))
                    "openWriteSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_WRITE_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(true)
                    }
                    "canManageAllFiles" ->
                        result.success(
                            Build.VERSION.SDK_INT >= 30 &&
                                Environment.isExternalStorageManager()
                        )
                    "openAllFilesAccessSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= 30) {
                            Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                        } else {
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "setRingtone" ->
                        setRingtone(call.argument<String>("path") ?: "", result)
                    "deleteFile" ->
                        deleteFile(call.argument<String>("path") ?: "", result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun setRingtone(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (path.isEmpty() || !file.exists()) {
            result.success(mapOf("ok" to false, "message" to "Audio file not found"))
            return
        }
        if (!Settings.System.canWrite(this)) {
            result.success(mapOf("ok" to false, "needsWriteSettings" to true))
            return
        }
        try {
            val uri = registerRingtone(file)
            if (uri == null) {
                result.success(mapOf("ok" to false, "message" to "Could not register ringtone"))
                return
            }
            RingtoneManager.setActualDefaultRingtoneUri(
                this, RingtoneManager.TYPE_RINGTONE, uri
            )
            result.success(mapOf("ok" to true, "message" to "Ringtone set"))
        } catch (e: Exception) {
            result.success(
                mapOf("ok" to false, "message" to (e.message ?: "Could not set ringtone"))
            )
        }
    }

    /// Copies the song into MediaStore's Ringtones folder and returns its
    /// content URI. Only ever replaces the copy this app created before.
    private fun registerRingtone(file: File): Uri? {
        val prefs = getSharedPreferences("audio_actions", Context.MODE_PRIVATE)
        val resolver = contentResolver

        prefs.getString("ringtone_uri", null)?.let { old ->
            try {
                resolver.delete(Uri.parse(old), null, null)
            } catch (_: Exception) {
            }
        }

        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase()) ?: "audio/mpeg"

        val uri = if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Audio.Media.TITLE, file.nameWithoutExtension)
                put(MediaStore.Audio.Media.MIME_TYPE, mime)
                put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_RINGTONES)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val newUri = resolver.insert(
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                values
            ) ?: return null
            resolver.openOutputStream(newUri)?.use { out ->
                FileInputStream(file).use { input -> input.copyTo(out) }
            } ?: return null
            resolver.update(
                newUri,
                ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) },
                null, null
            )
            newUri
        } else {
            // Pre-Q: legacy copy into the public Ringtones folder.
            val dest = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_RINGTONES),
                file.name
            )
            file.copyTo(dest, overwrite = true)
            resolver.insert(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                ContentValues().apply {
                    put(MediaStore.Audio.Media.DATA, dest.absolutePath)
                    put(MediaStore.Audio.Media.TITLE, dest.nameWithoutExtension)
                    put(MediaStore.Audio.Media.MIME_TYPE, mime)
                }
            )
        }

        if (uri != null) {
            prefs.edit().putString("ringtone_uri", uri.toString()).apply()
        }
        return uri
    }

    private fun deleteFile(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.success(mapOf("ok" to true, "message" to "Already removed"))
            return
        }
        val hasAllFiles =
            Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()
        var deleted = false

        if (hasAllFiles) {
            deleted = try {
                file.delete()
            } catch (_: Exception) {
                false
            }
        }

        if (!deleted) {
            // MediaStore delete — allowed for media the app may remove.
            try {
                resolverQuery(path)?.use { c ->
                    if (c.moveToFirst()) {
                        val uri = Uri.withAppendedPath(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                            c.getString(0)
                        )
                        deleted = contentResolver.delete(uri, null, null) > 0
                    }
                }
            } catch (_: Exception) {
            }
        }

        if (!deleted) {
            deleted = try {
                file.delete()
            } catch (_: Exception) {
                false
            }
        }

        when {
            deleted ->
                result.success(mapOf("ok" to true, "message" to "File deleted"))
            !hasAllFiles && Build.VERSION.SDK_INT >= 30 ->
                result.success(mapOf("ok" to false, "needsAllFiles" to true))
            else ->
                result.success(mapOf("ok" to false, "message" to "Could not delete file"))
        }
    }

    private fun resolverQuery(path: String) = try {
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Audio.Media._ID),
            "${MediaStore.Audio.Media.DATA} = ?",
            arrayOf(path),
            null
        )
    } catch (_: Exception) {
        null
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
