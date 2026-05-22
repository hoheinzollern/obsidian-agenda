package com.alessandrobruni.gtd

import android.app.Activity
import android.app.Dialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup.LayoutParams
import android.view.Window
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Headless dispatcher invoked by every widget row tap. The action extra
 * decides what to do:
 *   - ACTION_OPEN   → fire obsidian://open for the note (or fall back
 *                     to launching the main app).
 *   - ACTION_TOGGLE → flip the task's status on disk, mutate the cached
 *                     widget JSON, refresh the widget.
 */
class AgendaWidgetRowActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent.getStringExtra(AgendaWidgetFactory.EXTRA_ACTION)) {
            AgendaWidgetFactory.ACTION_TOGGLE -> {
                handleToggle()
                finish()
            }
            AgendaWidgetFactory.ACTION_OPEN -> {
                handleOpen()
                finish()
            }
            AgendaWidgetFactory.ACTION_PICK_STATUS -> {
                // AlertDialog needs the activity to stay alive; finishes
                // itself once the user picks or dismisses.
                showStatusPicker()
            }
            else -> finish()
        }
    }

    private fun handleOpen() {
        val relPath = intent.getStringExtra(AgendaWidgetFactory.EXTRA_REL_PATH)
        val vault = intent.getStringExtra(AgendaWidgetFactory.EXTRA_VAULT)
        if (relPath.isNullOrEmpty() || vault.isNullOrEmpty()) return

        val useAdvanced = HomeWidgetPlugin.getData(this)
            .getBoolean("agenda_use_advanced_uri", false)
        val line = intent.getIntExtra(AgendaWidgetFactory.EXTRA_LINE, -1)

        val uri = if (useAdvanced && line >= 0) {
            // Advanced URI plugin: jumps to the exact line. Line is
            // 1-based in the plugin's API.
            Uri.parse("obsidian://advanced-uri").buildUpon()
                .appendQueryParameter("vault", vault)
                .appendQueryParameter("filepath", relPath)
                .appendQueryParameter("line", (line + 1).toString())
                .build()
        } else {
            val fileNoExt = if (relPath.endsWith(".md")) {
                relPath.substring(0, relPath.length - 3)
            } else relPath
            Uri.parse("obsidian://open").buildUpon()
                .appendQueryParameter("vault", vault)
                .appendQueryParameter("file", fileNoExt)
                .build()
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, "Obsidian not installed", Toast.LENGTH_SHORT).show()
            packageManager.getLaunchIntentForPackage(packageName)?.let {
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(it)
            }
        }
    }

    private fun handleToggle() {
        val path = intent.getStringExtra(AgendaWidgetFactory.EXTRA_PATH)
        val line = intent.getIntExtra(AgendaWidgetFactory.EXTRA_LINE, -1)
        val rawLine = intent.getStringExtra(AgendaWidgetFactory.EXTRA_RAW_LINE)
        val status = intent.getStringExtra(AgendaWidgetFactory.EXTRA_STATUS)
        if (path.isNullOrEmpty() || line < 0 || rawLine.isNullOrEmpty() || status == null) {
            Toast.makeText(this, "Missing task data", Toast.LENGTH_SHORT).show()
            return
        }

        // TODO/WAIT → DONE; anything else → TODO. Matches Dart's
        // TaskCard._nextOnTap.
        val newMarker = when (status) {
            " ", "/" -> "x"
            else -> " "
        }
        applyStatus(path, line, rawLine, newMarker)
    }

    private fun showStatusPicker() {
        val path = intent.getStringExtra(AgendaWidgetFactory.EXTRA_PATH)
        val line = intent.getIntExtra(AgendaWidgetFactory.EXTRA_LINE, -1)
        val rawLine = intent.getStringExtra(AgendaWidgetFactory.EXTRA_RAW_LINE)
        val current = intent.getStringExtra(AgendaWidgetFactory.EXTRA_STATUS) ?: " "
        val title = intent.getStringExtra(AgendaWidgetFactory.EXTRA_TITLE) ?: "Task"
        if (path.isNullOrEmpty() || line < 0 || rawLine.isNullOrEmpty()) {
            finish()
            return
        }

        val dialog = Dialog(this)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setContentView(R.layout.status_picker)
        dialog.window?.apply {
            // Transparent OS-level window background so our rounded card
            // shape is what the user sees.
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setLayout((resources.displayMetrics.density * 280).toInt(), LayoutParams.WRAP_CONTENT)
        }
        dialog.setOnCancelListener { finish() }
        dialog.setOnDismissListener { finish() }

        dialog.findViewById<TextView>(R.id.status_picker_title).text = title

        // Show the checkmark next to the currently active status.
        val checkIds = mapOf(
            " " to R.id.status_picker_check_todo,
            "/" to R.id.status_picker_check_wait,
            "x" to R.id.status_picker_check_done,
            "-" to R.id.status_picker_check_cancelled,
        )
        checkIds[current]?.let { dialog.findViewById<View>(it).visibility = View.VISIBLE }

        val rowToMarker = listOf(
            R.id.status_picker_row_todo to " ",
            R.id.status_picker_row_wait to "/",
            R.id.status_picker_row_done to "x",
            R.id.status_picker_row_cancelled to "-",
        )
        for ((rowId, marker) in rowToMarker) {
            dialog.findViewById<LinearLayout>(rowId).setOnClickListener {
                dialog.dismiss()
                applyStatus(path, line, rawLine, marker)
                finish()
            }
        }

        dialog.show()
    }

    private fun applyStatus(
        path: String, line: Int, rawLine: String, newMarker: String,
    ) {
        val newLine = AgendaTaskWriter.setStatus(path, line, rawLine, newMarker)
        if (newLine == null) {
            Toast.makeText(
                this,
                "Could not update — file changed since the widget loaded. Open the app to refresh.",
                Toast.LENGTH_LONG
            ).show()
            return
        }
        AgendaWidgetRefresh.updateCachedJson(this, path, line, newMarker, newLine)
        AgendaWidgetRefresh.refreshAll(this)
    }
}
