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
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.KeyEvent
import android.webkit.MimeTypeMap
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.MediaButtonReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {
    private val widgetChannel = "omniversify/music_widget"
    private val actionChannel = "omniversify/audio_actions"
    private val openFileChannel = "omniversify/open_file"
    private val shareChannel = "omniversify/share_in"

    private var shareSink: EventChannel.EventSink? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupOpenFileChannel(flutterEngine)
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
        setupShareChannel(flutterEngine)
    }

    // ── Books another app opens with us ─────────────────────────────────

    /// Turns a file URI from an "Open with Omniversify" intent into a path
    /// Dart can read: `content://` URIs are streams behind someone else's
    /// permission, so the book is copied into this app's own storage first.
    /// The reader, the Library and the share button all want a real path.
    private fun setupOpenFileChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, openFileChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "materialize") {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("args", "No file to open.", null)
                    } else {
                        materialize(uri, result)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    // ── A caption or link another app sends us ─────────────────────────

    /// Waits for "Share to Omniversify". Dart subscribes once; anything that
    /// was handed to us before that sits in [pendingShare] and goes out the
    /// moment somebody listens.
    private fun setupShareChannel(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    shareSink = events
                    val waiting = pendingShare
                    pendingShare = null
                    if (waiting != null) events?.success(waiting)
                }

                override fun onCancel(arguments: Any?) {
                    shareSink = null
                }
            })
    }

    /// Pulls the words out of an ACTION_SEND intent — Instagram, a browser,
    /// anything with "Share to Omniversify" in its sheet — and pushes them to
    /// Dart if it is listening, otherwise parks them until it is.
    private fun handleShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return

        fun words(key: String): String =
            (intent.getStringExtra(key)
                ?: intent.getCharSequenceExtra(key)?.toString())
                ?.trim().orEmpty()

        val text = words(Intent.EXTRA_TEXT)
        val subject = words(Intent.EXTRA_SUBJECT)
        val hasFile = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) != null

        // Nothing but the tap on our own icon: let the app open normally.
        if (text.isEmpty() && subject.isEmpty() && !hasFile) return

        val payload = mapOf("text" to text, "subject" to subject)
        // Clear it so a recreated activity doesn't open the sheet twice.
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.removeExtra(Intent.EXTRA_SUBJECT)
        intent.removeExtra(Intent.EXTRA_STREAM)

        if (shareSink != null) {
            shareSink?.success(payload)
        } else {
            pendingShare = payload
        }
    }

    private fun materialize(uriString: String, result: MethodChannel.Result) {
        // Copying can take a while on a big comic — off the main thread.
        Thread {
            try {
                val uri = Uri.parse(uriString)
                val path = if (uri.scheme.isNullOrEmpty() || uri.scheme == "file") {
                    uri.path ?: throw IllegalArgumentException(
                        "That file is no longer on this phone."
                    )
                } else {
                    copyToImports(uri)
                }
                runOnUiThread { result.success(path) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("open", e.message ?: "That file couldn't be opened.", null)
                }
            }
        }.start()
    }

    private fun copyToImports(uri: Uri): String {
        val resolver = contentResolver

        // "msf:123" and friends carry no extension — borrow one from the type.
        var name = displayName(uri)
        if (!name.contains('.')) {
            name = "${name}.${extensionFor(resolver.getType(uri)) ?: "bin"}"
        }
        name = name.replace('/', '_')
        if (name.isBlank()) name = "book"

        val dest = File(File(filesDir, "imports").apply { mkdirs() }, name)

        // Re-opening a book already copied doesn't copy it all over again.
        val size = sizeOf(uri)
        if (dest.isFile && size > 0 && dest.length() == size) {
            return dest.absolutePath
        }

        val input = resolver.openInputStream(uri)
            ?: throw IllegalArgumentException("That file couldn't be opened.")
        input.use { stream ->
            FileOutputStream(dest).use { out -> stream.copyTo(out) }
        }
        return dest.absolutePath
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "book"
    }

    private fun sizeOf(uri: Uri): Long = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else -1L
            } ?: -1L
    } catch (_: Exception) {
        -1L
    }

    /// Android's name for a book's type, for the types its MIME map never
    /// got around to (the comics, for a start).
    private fun extensionFor(mime: String?): String? {
        if (mime.isNullOrBlank()) return null
        MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)?.let { return it }
        return when (mime) {
            "application/epub+zip" -> "epub"
            "application/x-cbz",
            "application/vnd.comicbook+zip",
            "application/comicbook+zip" -> "cbz"
            "application/x-cbr",
            "application/vnd.comicbook-rar",
            "application/x-rar-compressed",
            "application/rar" -> "cbr"
            else -> null
        }
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
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetAction(intent)
        handleShareIntent(intent)
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
