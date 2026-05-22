package com.alessandrobruni.gtd

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/**
 * Helpers for keeping the cached widget JSON and live widget UI in sync
 * after a widget-initiated change to a task.
 */
object AgendaWidgetRefresh {

    private val buckets = listOf("overdue", "today", "week", "next30", "floating")

    /**
     * Walks every bucket's cached JSON and updates the matching task's
     * status (or removes it if the new state closes the task). The
     * corresponding bucket count is decremented when a task drops out.
     *
     * This is simpler than tracking which bucket a task came from and
     * cheap because each list maxes out at ~200 entries.
     */
    fun updateCachedJson(
        context: Context,
        path: String,
        line: Int,
        newMarker: String,
        newRawLine: String,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val editor = prefs.edit()
        val closes = newMarker == "x" || newMarker == "-"
        for (bucket in buckets) {
            val key = "agenda_${bucket}_json"
            val raw = prefs.getString(key, "[]") ?: "[]"
            val arr = try { JSONArray(raw) } catch (e: Exception) { continue }
            val rebuilt = JSONArray()
            var removed = false
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                if (item.optString("path") == path && item.optInt("line", -1) == line) {
                    if (closes) {
                        removed = true
                        continue
                    }
                    item.put("status", newMarker)
                    item.put("raw_line", newRawLine)
                }
                rebuilt.put(item)
            }
            editor.putString(key, rebuilt.toString())
            if (removed) {
                val countKey = "agenda_${bucket}_count"
                val cur = prefs.getInt(countKey, 0)
                editor.putInt(countKey, (cur - 1).coerceAtLeast(0))
            }
        }
        editor.apply()
    }

    /** Force every installed widget instance to redraw + refetch its list. */
    fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(
            ComponentName(context, AgendaWidgetReceiver::class.java)
        )
        if (ids.isEmpty()) return
        val update = Intent(context, AgendaWidgetReceiver::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(update)
        for (id in ids) {
            mgr.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
        }
    }
}
