package com.alessandrobruni.gtd

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

class AgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        AgendaWidgetFactory(applicationContext)
}

class AgendaWidgetFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var tasks: List<JSONObject> = emptyList()
    private var vaultName: String = ""

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = HomeWidgetPlugin.getData(context)
        val bucket = prefs.getString("agenda_selected_bucket", "today") ?: "today"
        val key = "agenda_${bucket}_json"
        val json = prefs.getString(key, "[]") ?: "[]"
        vaultName = prefs.getString("agenda_vault_name", "") ?: ""
        tasks = try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    override fun onDestroy() {
        tasks = emptyList()
    }

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews {
        val t = tasks[position]
        val row = RemoteViews(context.packageName, R.layout.agenda_widget_item)

        val status = t.optString("status", " ")
        val desc = t.optString("description", "")
        val relPath = t.optString("rel_path", "")
        val absPath = t.optString("path", "")
        val line = t.optInt("line", -1)
        val rawLine = t.optString("raw_line", "")

        row.setImageViewResource(R.id.widget_row_checkbox, drawableFor(status))
        row.setTextViewText(R.id.widget_row_title, desc)

        // Tags line: "#admin · #hop · 📂 admin"
        val tagsArr = t.optJSONArray("tags")
        val source = t.optString("source", "")
        val tagBits = mutableListOf<String>()
        if (tagsArr != null) {
            for (i in 0 until tagsArr.length()) {
                tagBits.add("#${tagsArr.getString(i)}")
            }
        }
        if (source.isNotEmpty()) tagBits.add("📂 $source")
        if (tagBits.isNotEmpty()) {
            row.setTextViewText(
                R.id.widget_row_tags,
                tagBits.joinToString(" · ")
            )
            row.setViewVisibility(R.id.widget_row_tags, android.view.View.VISIBLE)
        } else {
            row.setViewVisibility(R.id.widget_row_tags, android.view.View.GONE)
        }

        // Body tap (title + tags column) → open the note in Obsidian.
        val openIntent = Intent().apply {
            putExtra(EXTRA_ACTION, ACTION_OPEN)
            putExtra(EXTRA_REL_PATH, relPath)
            putExtra(EXTRA_VAULT, vaultName)
            putExtra(EXTRA_LINE, line)
        }
        row.setOnClickFillInIntent(R.id.widget_row_body, openIntent)

        // Checkbox tap → toggle done/undone.
        val toggleIntent = Intent().apply {
            putExtra(EXTRA_ACTION, ACTION_TOGGLE)
            putExtra(EXTRA_PATH, absPath)
            putExtra(EXTRA_LINE, line)
            putExtra(EXTRA_RAW_LINE, rawLine)
            putExtra(EXTRA_STATUS, status)
        }
        row.setOnClickFillInIntent(R.id.widget_row_checkbox, toggleIntent)

        // ⋮ tap → state picker for all four states.
        val pickIntent = Intent().apply {
            putExtra(EXTRA_ACTION, ACTION_PICK_STATUS)
            putExtra(EXTRA_PATH, absPath)
            putExtra(EXTRA_LINE, line)
            putExtra(EXTRA_RAW_LINE, rawLine)
            putExtra(EXTRA_STATUS, status)
            putExtra(EXTRA_TITLE, desc)
        }
        row.setOnClickFillInIntent(R.id.widget_row_more, pickIntent)

        return row
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false

    companion object {
        const val EXTRA_ACTION = "agenda.action"
        const val EXTRA_REL_PATH = "agenda.rel_path"
        const val EXTRA_VAULT = "agenda.vault"
        const val EXTRA_PATH = "agenda.path"
        const val EXTRA_LINE = "agenda.line"
        const val EXTRA_RAW_LINE = "agenda.raw_line"
        const val EXTRA_STATUS = "agenda.status"
        const val EXTRA_TITLE = "agenda.title"

        const val ACTION_OPEN = "open"
        const val ACTION_TOGGLE = "toggle"
        const val ACTION_PICK_STATUS = "pick_status"

        fun drawableFor(statusMarker: String): Int = when (statusMarker) {
            "x", "X" -> R.drawable.widget_check_done
            "/" -> R.drawable.widget_check_wait
            "-" -> R.drawable.widget_check_cancelled
            else -> R.drawable.widget_check_blank
        }
    }
}
