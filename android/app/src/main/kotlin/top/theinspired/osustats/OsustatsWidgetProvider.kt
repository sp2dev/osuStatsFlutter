package top.theinspired.osustats

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.util.Log
import android.widget.RemoteViews
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray

open class OsustatsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, this::class.java)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Handle widget click via broadcast (Bug 8 fix: only write tapped ID on actual click)
        if (intent.action == ACTION_WIDGET_CLICK) {
            val appWidgetId = intent.getIntExtra(EXTRA_WIDGET_ID, 0)
            if (appWidgetId != 0) {
                try {
                    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit()
                        .putLong("flutter.last_tapped_widget_id", appWidgetId.toLong())
                        .putLong("flutter.pending_widget_$appWidgetId", 1L)
                        .commit()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to write tapped widget id", e)
                }

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                    context.startActivity(launchIntent)
                }
            }
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()

            for (appWidgetId in appWidgetIds) {
                val keysToRemove = listOf(
                    "flutter.widget_${appWidgetId}_username",
                    "flutter.widget_${appWidgetId}_mode_key",
                    "flutter.widget_${appWidgetId}_mode_display",
                    "flutter.widget_${appWidgetId}_field_key",
                    "flutter.widget_${appWidgetId}_field_label",
                    "flutter.widget_${appWidgetId}_time_range",
                    "flutter.widget_${appWidgetId}_custom_days",
                    "flutter.widget_${appWidgetId}_last_api_fetch",
                    "flutter.widget_${appWidgetId}_last_chart_render",
                    "flutter.widget_${appWidgetId}_current_value",
                    "flutter.widget_${appWidgetId}_raw_data",
                    "flutter.widget_${appWidgetId}_chart_path",
                    "flutter.pending_widget_${appWidgetId}"
                )
                for (key in keysToRemove) {
                    editor.remove(key)
                }

                // Remove from active list (Bug 1 fix: use JSON string, not StringSet)
                val activeIds = readActiveIds(prefs)
                activeIds.remove(appWidgetId.toString())
                writeActiveIds(editor, activeIds)

                // Delete chart PNG
                try {
                    val chartFile = File(context.cacheDir, "widget_charts/widget_$appWidgetId.png")
                    if (chartFile.exists()) chartFile.delete()
                } catch (_: Exception) {}
            }

            editor.commit()
        } catch (e: Exception) {
            Log.e(TAG, "onDeleted error", e)
        }
    }

    companion object {
        private const val TAG = "OsustatsWidget"
        internal const val PREFS_NAME = "FlutterSharedPreferences"
        const val ACTION_WIDGET_CLICK = "top.theinspired.osustats.WIDGET_CLICK"
        const val EXTRA_WIDGET_ID = "widget_id"

        // --- active_widget_ids helpers (Bug 1 fix: JSON string, not StringSet) ---

        private fun readActiveIds(prefs: SharedPreferences): MutableSet<String> {
            val str = prefs.getString("flutter.active_widget_ids", null)
            val result = mutableSetOf<String>()
            if (!str.isNullOrEmpty()) {
                try {
                    val arr = JSONArray(str)
                    for (i in 0 until arr.length()) {
                        result.add(arr.getString(i))
                    }
                } catch (_: Exception) {}
            }
            return result
        }

        private fun writeActiveIds(editor: SharedPreferences.Editor, ids: Set<String>) {
            val arr = JSONArray()
            for (id in ids) {
                arr.put(id)
            }
            editor.putString("flutter.active_widget_ids", arr.toString())
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            providerClass: Class<out AppWidgetProvider>
        ) {
            try {
                val prefs: SharedPreferences
                try {
                    prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                } catch (e: Exception) {
                    Log.e(TAG, "Cannot open prefs for $appWidgetId", e)
                    showFallback(context, appWidgetManager, appWidgetId, "无法读取配置")
                    return
                }

                // Determine layout
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                val isLarge = minWidth >= 200
                val layoutId = if (isLarge) R.layout.osustats_widget_4x2
                               else R.layout.osustats_widget_2x1

                val views = RemoteViews(context.packageName, layoutId)

                val username = prefs.getString("flutter.widget_${appWidgetId}_username", null)
                val configured = !username.isNullOrEmpty()

                if (!configured) {
                    // Try to apply pending global config
                    val pendingUser = prefs.getString("flutter.pending_global_username", null)
                    if (!pendingUser.isNullOrEmpty()) {
                        applyPendingConfig(prefs, appWidgetId, pendingUser)
                        showLoadingState(views, pendingUser, isLarge)
                        triggerBackgroundUpdate(context, appWidgetId)
                    } else {
                        showConfigPrompt(views, isLarge)
                    }
                } else {
                    showConfiguredState(context, prefs, views, appWidgetId, username, isLarge)
                    
                    // Check if cache is stale (>= 30 mins)
                    val lastFetch = prefs.getLong("flutter.widget_${appWidgetId}_last_api_fetch", 0L)
                    if (System.currentTimeMillis() - lastFetch >= 30 * 60 * 1000L) {
                        triggerBackgroundUpdate(context, appWidgetId)
                    }
                }

                // Setup click intent (Bug 8 fix: use broadcast, no prefs write here)
                setupClickIntent(context, views, appWidgetId, providerClass)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "updateWidget error for $appWidgetId", e)
                showFallback(context, appWidgetManager, appWidgetId, "数据暂不可用")
            }
        }

        private fun applyPendingConfig(
            prefs: SharedPreferences,
            appWidgetId: Int,
            pendingUser: String
        ) {
            val editor = prefs.edit()
            editor.putString("flutter.widget_${appWidgetId}_username", pendingUser)
            editor.putString("flutter.widget_${appWidgetId}_mode_key",
                prefs.getString("flutter.pending_global_mode_key", "osu_json") ?: "osu_json")
            editor.putString("flutter.widget_${appWidgetId}_mode_display",
                prefs.getString("flutter.pending_global_mode_display", "osu") ?: "osu")
            editor.putString("flutter.widget_${appWidgetId}_field_key",
                prefs.getString("flutter.pending_global_field_key", "pp") ?: "pp")
            editor.putString("flutter.widget_${appWidgetId}_field_label",
                prefs.getString("flutter.pending_global_field_label", "pp") ?: "pp")
            editor.putString("flutter.widget_${appWidgetId}_time_range",
                prefs.getString("flutter.pending_global_time_range", "7天") ?: "7天")
            // Bug 3 fix: use getLong instead of getInt (Flutter setInt stores as Long)
            editor.putLong("flutter.widget_${appWidgetId}_custom_days",
                prefs.getLong("flutter.pending_global_custom_days", 0L))

            // Clear pending global
            editor.remove("flutter.pending_global_username")
            editor.remove("flutter.pending_global_mode_key")
            editor.remove("flutter.pending_global_mode_display")
            editor.remove("flutter.pending_global_field_key")
            editor.remove("flutter.pending_global_field_label")
            editor.remove("flutter.pending_global_time_range")
            editor.remove("flutter.pending_global_custom_days")

            // Add to active list (Bug 1 fix: JSON string)
            val activeIds = readActiveIds(prefs)
            activeIds.add(appWidgetId.toString())
            writeActiveIds(editor, activeIds)

            // Use commit() for cross-process visibility
            editor.commit()
        }

        private fun showLoadingState(
            views: RemoteViews,
            username: String,
            isLarge: Boolean
        ) {
            views.setTextViewText(R.id.widget_stat_value, "加载中...")
            views.setTextViewText(R.id.widget_stat_label, "osu!")
            views.setTextViewText(R.id.widget_username, username)
            views.setTextViewText(R.id.widget_update_time, "等待首次更新")
            views.setViewVisibility(R.id.widget_chart, android.view.View.GONE)
            // No longer needed
            // if (!isLarge) {
            //     views.setViewVisibility(R.id.widget_text_area, android.view.View.VISIBLE)
            // }
        }

        private fun showConfigPrompt(views: RemoteViews, isLarge: Boolean) {
            views.setTextViewText(R.id.widget_stat_label,
                if (isLarge) "点击此处配置小组件" else "点击配置")
            views.setTextViewText(R.id.widget_stat_value, "osu!")
            views.setTextViewText(R.id.widget_username, "")
            views.setTextViewText(R.id.widget_update_time, "未配置")
            views.setViewVisibility(R.id.widget_chart, android.view.View.GONE)
            // No longer needed
            // if (!isLarge) {
            //     views.setViewVisibility(R.id.widget_text_area, android.view.View.VISIBLE)
            // }
        }

        private fun showConfiguredState(
            context: Context,
            prefs: SharedPreferences,
            views: RemoteViews,
            appWidgetId: Int,
            username: String,
            isLarge: Boolean
        ) {
            // Load chart bitmap
            val chartPath = prefs.getString("flutter.widget_${appWidgetId}_chart_path", null)
            var chartLoaded = false
            if (!chartPath.isNullOrEmpty()) {
                try {
                    val file = File(chartPath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(chartPath)
                        if (bitmap != null) {
                            views.setImageViewBitmap(R.id.widget_chart, bitmap)
                            views.setViewVisibility(R.id.widget_chart, android.view.View.VISIBLE)
                            chartLoaded = true
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to load chart bitmap", e)
                }
            }

            if (!chartLoaded) {
                views.setViewVisibility(R.id.widget_chart, android.view.View.GONE)
            }

            // Bug 5 fix: For 2x1, always keep text_area visible (show chart + text side by side)
            // No longer needed
            // if (!isLarge) {
            //     views.setViewVisibility(R.id.widget_text_area, android.view.View.VISIBLE)
            // }

            val statValue = prefs.getString("flutter.widget_${appWidgetId}_current_value", "-")
            views.setTextViewText(R.id.widget_stat_value, statValue ?: "-")

            val statLabel = prefs.getString("flutter.widget_${appWidgetId}_field_label", "")
            views.setTextViewText(R.id.widget_stat_label, statLabel ?: "")

            views.setTextViewText(R.id.widget_username, username)

            val lastUpdate = prefs.getLong("flutter.widget_${appWidgetId}_last_api_fetch", 0L)
            if (lastUpdate > 0) {
                val dateFormat = SimpleDateFormat("MM-dd HH:mm", Locale.getDefault())
                val dateStr = dateFormat.format(Date(lastUpdate))
                views.setTextViewText(R.id.widget_update_time, "$dateStr 更新")
            } else {
                views.setTextViewText(R.id.widget_update_time, "等待首次更新")
            }
        }

        private fun triggerBackgroundUpdate(context: Context, appWidgetId: Int) {
            try {
                val uri = android.net.Uri.parse("osustats://update?widgetId=$appWidgetId")
                val pendingIntent = es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast(context, uri)
                pendingIntent.send()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to trigger background update", e)
            }
        }

        // Bug 8 fix: Click sends a broadcast to the provider instead of writing prefs at setup
        private fun setupClickIntent(
            context: Context,
            views: RemoteViews,
            appWidgetId: Int,
            providerClass: Class<out AppWidgetProvider>
        ) {
            val intent = Intent(context, providerClass).apply {
                action = ACTION_WIDGET_CLICK
                putExtra(EXTRA_WIDGET_ID, appWidgetId)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, appWidgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
        }

        private fun showFallback(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            message: String
        ) {
            try {
                val views = RemoteViews(context.packageName, R.layout.osustats_widget_2x1)
                views.setTextViewText(R.id.widget_stat_label, message)
                views.setTextViewText(R.id.widget_stat_value, "!")
                views.setTextViewText(R.id.widget_username, "")
                views.setTextViewText(R.id.widget_update_time, "")
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (_: Exception) {}
        }
    }
}

/** Thin subclass for 4×2 widget — distinct manifest entry. */
class OsustatsWidgetProvider4x2 : OsustatsWidgetProvider()
