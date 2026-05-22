package com.alessandrobruni.gtd

import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Kotlin port of `lib/services/task_writer.dart`. The widget needs to
 * flip task state on disk without round-tripping through the Flutter
 * engine. Keep the two implementations behaviourally identical.
 *
 * Status markers:
 *   ' ' → TODO
 *   '/' → WAIT (in progress)
 *   'x' → DONE   (writes ✅ <date>)
 *   '-' → CANCELLED (writes ❌ <date>)
 */
object AgendaTaskWriter {

    private val doneStamp = Regex("\\s*✅\\s*\\d{4}-\\d{2}-\\d{2}")
    private val cancelledStamp = Regex("\\s*❌\\s*\\d{4}-\\d{2}-\\d{2}")
    private val checkbox = Regex("^(\\s*- \\[)([ xX/\\-])(\\])")

    /**
     * Returns the rewritten line on success, or null if the file has
     * drifted since the widget snapshot was taken (in which case we
     * refuse to write rather than corrupt the file).
     */
    fun setStatus(
        filePath: String,
        lineNumber: Int,
        expectedRawLine: String,
        newStatusMarker: String,
    ): String? {
        val file = File(filePath)
        if (!file.exists()) return null

        val originalContent = file.readText()
        val endsWithNewline = originalContent.endsWith("\n")
        val lines = originalContent.split("\n").toMutableList()
        // split("\n") with trailing newline produces an empty last element;
        // strip it so lineNumber indexing matches Dart's readAsLines().
        if (endsWithNewline && lines.isNotEmpty() && lines.last().isEmpty()) {
            lines.removeAt(lines.size - 1)
        }

        if (lineNumber < 0 || lineNumber >= lines.size) return null
        if (lines[lineNumber] != expectedRawLine) return null

        val newLine = writeStatus(lines[lineNumber], newStatusMarker) ?: return null
        lines[lineNumber] = newLine

        val out = lines.joinToString("\n") + if (endsWithNewline) "\n" else ""
        file.writeText(out)
        return newLine
    }

    private fun writeStatus(line: String, marker: String): String? {
        val m = checkbox.find(line) ?: return null
        val groups = m.groupValues
        var newLine = line.replaceFirst(checkbox, "${groups[1]}$marker${groups[3]}")
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

        when (marker) {
            "x", "X" -> {
                newLine = newLine.replace(cancelledStamp, "")
                if (!doneStamp.containsMatchIn(newLine)) {
                    newLine = newLine.trimEnd() + " ✅ $today"
                }
            }
            "-" -> {
                newLine = newLine.replace(doneStamp, "")
                if (!cancelledStamp.containsMatchIn(newLine)) {
                    newLine = newLine.trimEnd() + " ❌ $today"
                }
            }
            else -> {
                // TODO or WAIT: strip both stamps.
                newLine = newLine.replace(doneStamp, "")
                newLine = newLine.replace(cancelledStamp, "")
            }
        }
        return newLine.replace(Regex(" {2,}"), " ").trimEnd()
    }
}
