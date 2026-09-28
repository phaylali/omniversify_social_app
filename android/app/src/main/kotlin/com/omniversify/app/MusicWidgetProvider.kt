package com.omniversify.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class MusicWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val title = prefs.getString("widget_title", "Nothing playing") ?: "Nothing playing"
        val artist = prefs.getString("widget_artist", "Omniversify") ?: "Omniversify"
        val isPlaying = prefs.getBoolean("widget_is_playing", false)
        val artUri = prefs.getString("widget_artwork_uri", null)

        val views = RemoteViews(context.packageName, R.layout.music_widget)
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)
        views.setImageViewResource(
            R.id.widget_play_pause,
            if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        )

        // file:// URIs in private storage are unreadable by the launcher —
        // decode the bitmap here (app process) and push it via RemoteViews.
        setArtwork(views, artUri)

        // Background of the widget opens the app; buttons only send media keys.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            launchIntent(context)
        )
        views.setOnClickPendingIntent(
            R.id.widget_play_pause,
            mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 1)
        )
        views.setOnClickPendingIntent(
            R.id.widget_next,
            mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 2)
        )
        views.setOnClickPendingIntent(
            R.id.widget_previous,
            mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 3)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun setArtwork(views: RemoteViews, artUri: String?) {
        val fallback = R.drawable.app_logo
        if (artUri.isNullOrEmpty()) {
            views.setImageViewResource(R.id.widget_artwork, fallback)
            return
        }
        try {
            val uri = Uri.parse(artUri)
            val path = when {
                uri.scheme == "file" && uri.path != null -> uri.path!!
                artUri.startsWith("/") -> artUri
                else -> null
            }
            if (path == null) {
                views.setImageViewResource(R.id.widget_artwork, fallback)
                return
            }
            val bitmap = decodeScaled(path, 512, 512)
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_artwork, bitmap)
            } else {
                views.setImageViewResource(R.id.widget_artwork, fallback)
            }
        } catch (_: Exception) {
            views.setImageViewResource(R.id.widget_artwork, fallback)
        }
    }

    private fun decodeScaled(path: String, maxW: Int, maxH: Int): Bitmap? {
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxW &&
                bounds.outHeight / (sample * 2) >= maxH
            ) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            BitmapFactory.decodeFile(path, opts)
        } catch (_: Exception) {
            null
        }
    }

    private fun launchIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /// Control playback via MediaButtonReceiver — does not open MainActivity.
    private fun mediaButtonIntent(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(context, MediaButtonReceiver::class.java).apply {
            action = Intent.ACTION_MEDIA_BUTTON
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, MusicWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val intent = Intent(context, MusicWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
