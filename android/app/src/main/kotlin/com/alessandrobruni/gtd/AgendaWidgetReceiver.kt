package com.alessandrobruni.gtd

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class AgendaWidgetReceiver : HomeWidgetProvider() {

    private val buckets = listOf("overdue", "today", "week", "next30", "floating")

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        val selected = widgetData.getString("agenda_selected_bucket", "today") ?: "today"
        val opacityPct = widgetData.getInt("agenda_widget_opacity", 90).coerceIn(0, 100)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.agenda_widget)
            views.setFloat(R.id.widget_bg, "setAlpha", opacityPct / 100f)

            renderChip(views, R.id.widget_chip_overdue, "overdue", "⚠️",
                widgetData.getInt("agenda_overdue_count", 0), selected, context, widgetId)
            renderChip(views, R.id.widget_chip_today, "today", "📅",
                widgetData.getInt("agenda_today_count", 0), selected, context, widgetId)
            renderChip(views, R.id.widget_chip_week, "week", "📆",
                widgetData.getInt("agenda_week_count", 0), selected, context, widgetId)
            renderChip(views, R.id.widget_chip_next30, "next30", "🔜",
                widgetData.getInt("agenda_next30_count", 0), selected, context, widgetId)
            renderChip(views, R.id.widget_chip_floating, "floating", "📂",
                widgetData.getInt("agenda_floating_count", 0), selected, context, widgetId)

            // Wire the ListView to the RemoteViewsService.
            val serviceIntent = Intent(context, AgendaWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = android.net.Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_list, serviceIntent)

            val rowTemplate = Intent(context, AgendaWidgetRowActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val rowPending = PendingIntent.getActivity(
                context, widgetId, rowTemplate,
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setPendingIntentTemplate(R.id.widget_list, rowPending)

            val count = widgetData.getInt("agenda_${selected}_count", 0)
            if (count > 0) {
                views.setViewVisibility(R.id.widget_list, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_list, android.view.View.GONE)
                views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
            }

            // Tap on empty state opens the main app.
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                val pi = PendingIntent.getActivity(
                    context, 0, it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                views.setOnClickPendingIntent(R.id.widget_empty, pi)
            }

            // Tap on "+" → launches the app with a URI the Flutter side
            // recognises as "open quick-add sheet".
            val quickAddPi = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("obsidian-agenda://quick-add"),
            )
            views.setOnClickPendingIntent(R.id.widget_add_inbox, quickAddPi)

            appWidgetManager.updateAppWidget(widgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.widget_list)
        }
    }

    private fun renderChip(
        views: RemoteViews,
        viewId: Int,
        bucket: String,
        emoji: String,
        count: Int,
        selected: String,
        context: Context,
        widgetId: Int,
    ) {
        views.setTextViewText(viewId, "$emoji $count")
        val bg = if (bucket == selected)
            R.drawable.widget_chip_selected
        else R.drawable.widget_chip
        views.setInt(viewId, "setBackgroundResource", bg)

        // Each chip click broadcasts the new selected bucket.
        val intent = Intent(context, AgendaSetFilterReceiver::class.java).apply {
            action = AgendaSetFilterReceiver.ACTION_SET
            putExtra(AgendaSetFilterReceiver.EXTRA_BUCKET, bucket)
        }
        val requestCode = widgetId * 10 + buckets.indexOf(bucket)
        val pi = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        views.setOnClickPendingIntent(viewId, pi)
    }
}
