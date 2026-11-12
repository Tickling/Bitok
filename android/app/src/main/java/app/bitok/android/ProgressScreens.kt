@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Прогресс ученика: рейтинг, уровень, радар пяти навыков, динамика; трофеи и медали.
package app.bitok.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun ProgressScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    val progress = b.progress(app.me)
    val rating = b.rating(app.me)
    Screen("Прогресс", app, actions = {
        androidx.compose.material3.TextButton({ app.push(Route.Exercises(app.me)) }) { Text("📋 Упражнения") }
    }) {
        GlassCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Secondary("Общий рейтинг")
                    Text(rating?.toString() ?: "—", fontSize = 44.sp, fontWeight = FontWeight.Bold, color = p.accent)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Secondary("Уровень")
                    Text(b.level(rating), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
                }
            }
        }
        if (progress.isEmpty()) {
            Secondary("Оценок пока нет — после тренировки тренер оценит 5 навыков от 0 до 100.", size = 15)
        } else {
            GlassCard {
                Title("Навыки")
                Radar(progress)
                Metric.entries.forEach { MetricBar(it.title, progress[it] ?: 0) }
            }
            val history = b.history(app.me)
            if (history.size > 1) {
                GlassCard {
                    Title("Динамика рейтинга")
                    val accent = p.accent
                    Canvas(Modifier.fillMaxWidth().height(120.dp)) {
                        val max = 100f
                        val step = size.width / (history.size - 1)
                        val path = Path()
                        history.forEachIndexed { i, (_, value) ->
                            val point = Offset(i * step, size.height - value / max * size.height)
                            if (i == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
                            drawCircle(accent, 5f, point)
                        }
                        drawPath(path, accent, style = Stroke(width = 5f))
                    }
                    Row { history.forEach { (at, v) -> Secondary("${Fmt.shortDay(at).substringAfter(", ")}\n$v", Modifier.weight(1f), 11) } }
                }
            }
            b.state.evaluations.filter { it.studentId == app.me }.maxByOrNull { it.at }?.comment?.let {
                GlassCard {
                    Title("Комментарий тренера")
                    Text("«$it»", color = p.text)
                }
            }
        }
    }
}

@Composable
private fun Radar(values: Map<Metric, Int>) {
    val p = LocalPalette.current
    val metrics = Metric.entries
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        Canvas(Modifier.width(220.dp).height(200.dp)) {
            val center = Offset(size.width / 2, size.height / 2)
            val radius = size.minDimension / 2 * 0.9f
            fun point(i: Int, fraction: Float): Offset {
                val angle = -PI / 2 + 2 * PI * i / metrics.size
                return Offset(center.x + (cos(angle) * radius * fraction).toFloat(), center.y + (sin(angle) * radius * fraction).toFloat())
            }
            for (ring in 1..4) {
                val path = Path()
                metrics.indices.forEach { i -> val pt = point(i, ring / 4f); if (i == 0) path.moveTo(pt.x, pt.y) else path.lineTo(pt.x, pt.y) }
                path.close()
                drawPath(path, p.textSecondary.copy(alpha = 0.25f), style = Stroke(1.5f))
            }
            val shape = Path()
            metrics.forEachIndexed { i, m -> val pt = point(i, (values[m] ?: 0) / 100f); if (i == 0) shape.moveTo(pt.x, pt.y) else shape.lineTo(pt.x, pt.y) }
            shape.close()
            drawPath(shape, p.accent.copy(alpha = 0.3f))
            drawPath(shape, p.accent, style = Stroke(4f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            metrics.forEach { Text("${it.short} ${values[it] ?: 0}", fontSize = 12.sp, color = p.textSecondary) }
        }
    }
}

@Composable
fun TrophiesScreen(app: AppState) {
    val p = LocalPalette.current
    Screen("Трофеи", app) {
        GlassCard {
            Row {
                listOf("3" to "турнира", "75%" to "побед", "131" to "шар забит").forEach { (v, t) ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(v, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.accent)
                        Secondary(t)
                    }
                }
            }
        }
        Title("Медали")
        listOf(
            Triple("🥇", "Кубок «Флагмана» — 1 место", "4 из 4 побед · 61 шар"),
            Triple("🥉", "Осенний турнир — 3 место", "3 из 4 побед · 48 шаров"),
            Triple("🎗", "Открытый турнир — участник", "Медаль за участие · 22 шара"),
        ).forEach { (icon, title, details) ->
            GlassCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(icon, fontSize = 34.sp)
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(title, fontWeight = FontWeight.SemiBold, color = p.text)
                        Secondary(details)
                    }
                }
            }
        }
    }
}
