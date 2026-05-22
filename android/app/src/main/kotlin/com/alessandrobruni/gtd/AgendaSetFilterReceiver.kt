package com.alessandrobruni.gtd

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin

/** Persists the user-selected bucket and refreshes every installed widget. */
class AgendaSetFilterReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val bucket = intent.getStringExtra(EXTRA_BUCKET) ?: return
        HomeWidgetPlugin.getData(context).edit()
            .putString("agenda_selected_bucket", bucket).apply()
        AgendaWidgetRefresh.refreshAll(context)
    }

    companion object {
        const val EXTRA_BUCKET = "agenda.bucket"
        const val ACTION_SET = "com.alessandrobruni.gtd.SET_FILTER"
    }
}
