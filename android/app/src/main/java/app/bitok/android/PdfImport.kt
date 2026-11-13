@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Тренер загружает PDF с упражнениями: текст извлекается из PDF (PdfBox), из него — номер, название,
// координаты битка и шаров («Биток 70:40», «по линии 60»), луза и винт. Тренер проверяет схемы и сохраняет.
// Для сканов без текстового слоя — ручное добавление (в iOS-версии работает распознавание на устройстве).
package app.bitok.android

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object PdfExerciseImporter {
    fun text(context: Context, uri: Uri): String = runCatching {
        PDFBoxResourceLoader.init(context)
        context.contentResolver.openInputStream(uri)?.use { input -> PDDocument.load(input).use { PDFTextStripper().getText(it) } } ?: ""
    }.getOrDefault("")

    fun parse(text: String, coachId: String): List<Exercise> {
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val level = lines.firstOrNull { it.lowercase().contains("уровень") } ?: "Из PDF"
        val header = Regex("""[Уу]пражнени[ея]\s*[№N#]?\s*(\d+)""")
        val result = mutableListOf<Exercise>()
        var number: Int? = null
        var body = mutableListOf<String>()
        fun flush() { number?.let { result += exercise(it, body, level, coachId) } }
        for (line in lines) {
            val match = header.find(line)
            if (match != null) { flush(); number = match.groupValues[1].toInt(); body = mutableListOf() } else if (number != null) body += line
        }
        flush()
        return result
    }

    fun exercise(number: Int, lines: List<String>, level: String, coachId: String): Exercise {
        val all = lines.joinToString(" ").lowercase()
        fun pairs(prefix: String) = Regex(prefix + """\s*(\d{1,3})\s*[:;.,]\s*(\d{1,3})""").findAll(all).mapNotNull { m ->
            val x = m.groupValues[1].toDouble(); val y = m.groupValues[2].toDouble()
            if (x <= 160 && y <= 80) TablePoint(x, y) else null
        }.toList()
        var cue = pairs("биток")
        val objects = pairs("шар")
        if (cue.isEmpty()) cue = Regex("""лини[ия]\s*(\d{1,3})""").findAll(all).map { TablePoint(minOf(it.groupValues[1].toDouble(), 155.0), 45.0) }.toList()
        if (cue.isEmpty()) cue = listOf(TablePoint(70.0, 40.0))
        val target = when {
            all.contains("середин") && !all.contains("через середину") -> Pocket.TOP_MIDDLE
            (all.contains("возврат") || all.contains("силой") || all.contains("борт")) && !all.contains("угол") -> Pocket.SHORT_RAIL
            else -> Pocket.TOP_LEFT
        }
        val metric = when {
            all.contains("винт") && !all.contains("винт 0") -> Metric.TACTICS
            all.contains("мост") || all.contains("стойк") || all.contains("машинк") -> Metric.STANCE
            all.contains("сил") || all.contains("возврат") -> Metric.CUE_BALL
            target == Pocket.TOP_MIDDLE -> Metric.AIMING
            else -> Metric.POSITION
        }
        val attempts = Regex("""(\d{1,2})\s*удар""").find(all)?.groupValues?.get(1)?.toInt() ?: 10
        return Exercise("pdf-${newId().take(8)}-$number", number, level, lines.firstOrNull() ?: "Упражнение №$number", lines.drop(1), metric,
            cue, objects, listOf(target), maxOf(1, attempts), metric == Metric.TACTICS, all.contains("пирамид"), coachId)
    }
}

@Composable
fun CoachExercisesScreen(app: AppState) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val b = app.backend
    var processing by remember { mutableStateOf(false) }
    val found = remember { mutableStateListOf<Exercise>() }
    var reviewed by remember { mutableStateOf(false) }
    var manual by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        processing = true
        scope.launch {
            val text = withContext(Dispatchers.IO) { PdfExerciseImporter.text(context, uri) }
            found.clear(); found.addAll(PdfExerciseImporter.parse(text, app.me))
            processing = false; reviewed = true
            if (found.isEmpty()) app.error = "В файле не найден текст упражнений (похоже на скан). Добавьте упражнения вручную или загрузите PDF с текстом."
        }
    }
    Screen("Упражнения и уроки", app) {
        GlassCard {
            Title("Загрузите PDF с упражнениями")
            Secondary("Приложение найдёт упражнения, координаты шаров («Биток 70:40», «по линии 60»), лузу и винт и построит схему. Перед сохранением вы проверите результат.", size = 14)
            PrimaryButton(if (processing) "Читаю PDF…" else "Выбрать PDF", enabled = !processing) { picker.launch(arrayOf("application/pdf")) }
            TextButton({ manual = !manual }) { Text(if (manual) "Скрыть ручное добавление" else "+ Добавить вручную") }
        }
        if (manual) ManualExerciseEditor(app) { b.saveImported(listOf(it)); manual = false; app.info = "Упражнение добавлено" }
        if (reviewed && found.isNotEmpty()) {
            Title("Найдено: ${found.size}")
            found.toList().forEach { e ->
                GlassCard {
                    Row { Secondary("№${e.number} · ${e.metric.title}", Modifier.weight(1f)); TextButton({ found.remove(e) }) { Text("Убрать") } }
                    Title(e.title)
                    TableScheme(e, labels = false)
                    e.details.forEach { Secondary(it, size = 12) }
                }
            }
            PrimaryButton("Сохранить ${found.size}") { b.saveImported(found.toList()); found.clear(); reviewed = false; app.info = "Упражнения сохранены" }
        }
        b.allExercises.groupBy { it.level }.toSortedMap().forEach { (level, list) ->
            Title(level)
            list.sortedBy { it.number }.forEach { ExerciseRow(app, it, null, 0, app.me) }
        }
    }
}
