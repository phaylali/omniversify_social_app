package com.omniversify.omniversify_social_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetPlugin

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

        if (!artUri.isNullOrEmpty()) {
            try {
                views.setImageViewUri(R.id.widget_artwork, Uri.parse(artUri))
            } catch (_: Exception) {
                views.setImageViewResource(
                    R.id.widget_artwork,
                    android.R.drawable.ic_menu_gallery
                )
            }
        }

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
