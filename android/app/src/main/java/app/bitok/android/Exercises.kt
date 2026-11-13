@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Упражнения подготовительного уровня (методичка тренера), схема стола, результаты, статистика и сравнение.
package app.bitok.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

private fun p(x: Double, y: Double) = TablePoint(x, y)
private val SPINS = listOf("Винт 1 Глубина 2", "Винт 2 Глубина 2", "Винт 3 Глубина 2 и 3", "Винт 4 Глубина 2", "Винт 5 Глубина 2",
    "Винт 6 Глубина 2", "Винт 7 Глубина 2", "Винт 8 Глубина 2", "Винт 9 Глубина 2 и 3", "Винт 10 Глубина 2", "Винт 11 Глубина 2", "Винт 12 Глубина 2")

/** «Подготовительный уровень» — 16 упражнений из методички. «По линии N» — линия от отметки N нижнего борта к лузе. */
val PreparatoryExercises = listOf(
    Exercise("prep-1", 1, title = "Забить биток в середину с точки", details = listOf("Биток 70:40. Винт 0.",
        "а) Сделать 10 ударов. Записать количество забитых шаров.", "б) Сделать 10 ударов, только после первой паузы закрыть глаза (чтобы научиться видеть руку)."),
        metric = Metric.AIMING, cueBalls = listOf(p(70.0, 40.0)), targets = listOf(Pocket.TOP_MIDDLE)),
    Exercise("prep-2", 2, title = "Забить биток в угол", details = listOf("Биток 50:50. Винт 0."),
        metric = Metric.POSITION, cueBalls = listOf(p(50.0, 50.0)), targets = listOf(Pocket.TOP_LEFT)),
    Exercise("prep-3", 3, title = "Забить биток в середину с разных точек", details = listOf("Биток по линиям 60, 50, 40, 100, 110, 120 (на горизонтали 40)."),
        metric = Metric.AIMING, cueBalls = listOf(p(70.0, 40.0), p(65.0, 40.0), p(60.0, 40.0), p(90.0, 40.0), p(95.0, 40.0), p(100.0, 40.0)),
        targets = listOf(Pocket.TOP_MIDDLE)),
    Exercise("prep-4", 4, title = "Забить биток в угол с разных точек",
        details = listOf("Биток по линиям 50, 60, 70 — в левый угол; 90, 100, 110 — в правый (на горизонтали 50)."),
        metric = Metric.POSITION, cueBalls = listOf(p(31.0, 50.0), p(37.5, 50.0), p(44.0, 50.0), p(116.0, 50.0), p(122.5, 50.0), p(129.0, 50.0)),
        targets = List(3) { Pocket.TOP_LEFT } + List(3) { Pocket.TOP_RIGHT }),
    Exercise("prep-5", 5, title = "Забить биток в угол с разных точек (дальние)", details = listOf("Биток по линиям 80, 100, 120 (на горизонтали 55)."),
        metric = Metric.POSITION, cueBalls = listOf(p(55.0, 55.0), p(69.0, 55.0), p(82.5, 55.0)), targets = listOf(Pocket.TOP_LEFT)),
    Exercise("prep-6", 6, title = "Забить биток в угол: мост с борта",
        details = listOf("Отработать мост с борта, когда биток находится на горизонтальной линии 65 с различных точек.",
            "Биток по линиям 60, 50, 40 — в левый угол; 120, 110, 100 — в правый."),
        metric = Metric.STANCE, cueBalls = listOf(p(48.75, 65.0), p(40.6, 65.0), p(32.5, 65.0), p(127.5, 65.0), p(119.4, 65.0), p(111.25, 65.0)),
        targets = List(3) { Pocket.TOP_LEFT } + List(3) { Pocket.TOP_RIGHT }),
    Exercise("prep-7", 7, title = "Забить биток в середину",
        details = listOf("Биток 70:75. Винт 12. Глубина 2.", "Отработать стойку и мост к битку, стоящему близко к борту.",
            "В этом случае тело необходимо расположить вдоль линии удара.",
            "Правая нога чуть заступает за линию удара, ноги широко расставлены, опорная нога — левая (для правши), левая рука прямая, кий держим ближе к центру тяжести."),
        metric = Metric.STANCE, cueBalls = listOf(p(70.0, 75.0)), targets = listOf(Pocket.TOP_MIDDLE), spin = true),
    Exercise("prep-8", 8, title = "Забить биток в середину, мост через шар",
        details = listOf("Биток 80:40. Шар 80:60.", "Как и в прошлом упражнении, стойка с разворотом тела вдоль линии удара.", "Мост поднять максимально вверх."),
        metric = Metric.STANCE, cueBalls = listOf(p(80.0, 40.0)), objectBalls = listOf(p(80.0, 60.0)), targets = listOf(Pocket.TOP_MIDDLE)),
    Exercise("prep-9", 9, title = "Забить биток в угол через середину стола",
        details = listOf("Биток по линии 140.", "Биток по линии 0.", "Биток по линии 60 (короткого борта)."),
        metric = Metric.POSITION, cueBalls = listOf(p(120.0, 44.0), p(120.0, 60.0), p(103.0, 60.0)), targets = listOf(Pocket.TOP_LEFT)),
    Exercise("prep-10", 10, title = "Забить биток в угол через середину стола", details = listOf("Биток 155:60."),
        metric = Metric.POSITION, cueBalls = listOf(p(155.0, 60.0)), targets = listOf(Pocket.TOP_LEFT)),
    Exercise("prep-11", 11, title = "Забить биток в угол с машинки",
        details = listOf("Биток 20:60.", "Отработать правильное положение кисти в рабочей руке при ударе с машинкой."),
        metric = Metric.STANCE, cueBalls = listOf(p(20.0, 60.0)), targets = listOf(Pocket.TOP_LEFT)),
    Exercise("prep-12", 12, title = "Возврат битка от короткого борта на кий",
        details = listOf("Биток 120:40. Винт 0.", "Биток катится к дальнему короткому борту и возвращается точно на кий."),
        metric = Metric.CUE_BALL, cueBalls = listOf(p(120.0, 40.0)), targets = listOf(Pocket.SHORT_RAIL)),
    Exercise("prep-13", 13, title = "Удар по битку с различной силой",
        details = listOf("Биток 120:20.",
            "Первый удар — докатить биток до короткого борта. Условно обозначить силу удара 0,75, так как с точки 120:20 до короткого борта биток проходит 3/4 стола.",
            "Далее прибавляем по 1/4 стола: следующий удар по силе будет равен 1. И так далее до силы удара, равной 3.",
            "Итого 10 ударов с различной силой: 0,75; 1; 1,25; 1,5; 1,75; 2; 2,25; 2,5; 2,75; 3."),
        metric = Metric.CUE_BALL, cueBalls = listOf(p(120.0, 20.0)), targets = listOf(Pocket.SHORT_RAIL)),
    Exercise("prep-14", 14, title = "Забить биток в середину с различными винтами",
        details = listOf("Биток 80:40.", "Объяснить ученику 12-координатную систему винтов. Объяснить, как правильно ставить мост и выбирать направление удара при ударе с винтом.") + SPINS,
        metric = Metric.TACTICS, cueBalls = listOf(p(80.0, 40.0)), targets = listOf(Pocket.TOP_MIDDLE), attempts = 12, spin = true),
    Exercise("prep-15", 15, title = "Биток в угол с различными винтами", details = listOf("Биток 50:50.") + SPINS,
        metric = Metric.TACTICS, cueBalls = listOf(p(50.0, 50.0)), targets = listOf(Pocket.TOP_LEFT), attempts = 12, spin = true),
    Exercise("prep-16", 16, title = "Разбить пирамиду и забить все шары",
        details = listOf("Разбить пирамиду в первый шар и забить все шары по одному за 16 ударов.", "Пирамида — первый шар на отметке 45:40, биток 120:40."),
        metric = Metric.POSITION, cueBalls = listOf(p(120.0, 40.0)), targets = emptyList(), attempts = 16, rack = true),
)

// region Хранилище

val DemoBackend.allExercises: List<Exercise> get() = PreparatoryExercises + ShotSamples + state.customExercises
fun DemoBackend.exercise(id: String) = allExercises.firstOrNull { it.id == id }
fun DemoBackend.results(studentId: String, exerciseId: String? = null) =
    state.exerciseResults.filter { it.studentId == studentId && (exerciseId == null || it.exerciseId == exerciseId) }.sortedBy { it.at }

/** Уровень по упражнению: средний процент трёх последних подходов. */
fun DemoBackend.exerciseLevel(studentId: String, exerciseId: String): Int? {
    val last = results(studentId, exerciseId).takeLast(3)
    return if (last.isEmpty()) null else last.sumOf { it.percent } / last.size
}

fun DemoBackend.addResults(items: List<ExerciseResult>) = update { it.copy(exerciseResults = it.exerciseResults + items) }
fun DemoBackend.saveImported(items: List<Exercise>) = update { s ->
    s.copy(customExercises = s.customExercises.filterNot { old -> items.any { it.id == old.id } } + items)
}
fun DemoBackend.stars(studentId: String, exerciseId: String) = state.stars["$studentId|$exerciseId"] ?: 0

fun DemoBackend.recordTraining(exercise: Exercise, studentId: String, made: Int, attempts: Int, stars: Int) = update { s ->
    val key = "$studentId|${exercise.id}"
    s.copy(stars = s.stars + (key to maxOf(s.stars[key] ?: 0, stars)),
        exerciseResults = s.exerciseResults + ExerciseResult(newId(), studentId, studentId, exercise.id, made, maxOf(1, attempts), now()))
}

/** Демо-история результатов, чтобы статистика и сравнение были не пустыми. */
fun DemoBackend.seedResults(): List<ExerciseResult> {
    val plan = mapOf(
        Ids.IVAN to mapOf("prep-1" to listOf(5, 6, 8), "prep-2" to listOf(4, 6, 7), "prep-3" to listOf(3, 5), "prep-7" to listOf(4, 5), "prep-12" to listOf(6, 7), "prep-14" to listOf(5, 7)),
        Ids.MARIA to mapOf("prep-1" to listOf(7, 8), "prep-2" to listOf(6, 7), "prep-4" to listOf(5), "prep-12" to listOf(8), "prep-15" to listOf(4)),
        Ids.NATASHA to mapOf("prep-1" to listOf(4, 5), "prep-2" to listOf(3, 5), "prep-8" to listOf(6), "prep-13" to listOf(5, 6)),
    )
    var day = -30L
    val result = mutableListOf<ExerciseResult>()
    for ((student, map) in plan) for ((exerciseId, values) in map) {
        val attempts = PreparatoryExercises.first { it.id == exerciseId }.attempts
        values.forEachIndexed { i, made ->
            result += ExerciseResult(newId(), student, Ids.ALEXEY, exerciseId, minOf(made, attempts), attempts, now() + (day + i * 9) * 86_400_000L)
        }
        day += 1
    }
    return result
}

// endregion

// region Схема стола

/** Стол 160×80 как в методичке: цифры на бортах, пунктир до бортов, стрелка удара, «часы» винта, штатив. */
@Composable
fun TableScheme(exercise: Exercise, modifier: Modifier = Modifier, labels: Boolean = true, showTripod: Boolean = false, showAim: Boolean = false) {
    Canvas(modifier.fillMaxWidth().aspectRatio(if (labels) 1.95f else 2.1f).background(if (labels) Color.White else Color.Transparent)) {
        val margin = if (labels) size.width * 0.05f else 0f
        val tableW = size.width - margin * 2; val tableH = size.height - margin * 2
        val rail = tableW * 0.035f
        val fx = margin + rail; val fy = margin + rail; val fw = tableW - rail * 2; val fh = tableH - rail * 2
        fun map(p: TablePoint) = Offset(fx + (p.x / 160 * fw).toFloat(), fy + (p.y / 80 * fh).toFloat())
        val ball = fw / 160 * 4.6f
        drawRoundRect(Color(0xFF855408), Offset(margin, margin), Size(tableW, tableH), CornerRadius(rail, rail))
        drawRect(Color(0xFF5C9A12), Offset(fx, fy), Size(fw, fh))
        val paint = android.graphics.Paint().apply { color = android.graphics.Color.BLACK; textSize = maxOf(14f, size.width / 70); isFakeBoldText = true; textAlign = android.graphics.Paint.Align.CENTER }
        for (i in 10 until 160 step 10) if (i != 80) {
            val x = fx + i / 160f * fw
            for (y in listOf(margin + rail / 2, margin + tableH - rail / 2)) drawCircle(Color.White, 2.5f, Offset(x, y))
            if (labels) {
                drawContext.canvas.nativeCanvas.drawText("$i", x, margin * 0.7f, paint)
                drawContext.canvas.nativeCanvas.drawText("$i", x, size.height - margin * 0.2f, paint)
            }
        }
        for (i in 10 until 80 step 10) {
            val y = fy + i / 80f * fh
            for (x in listOf(margin + rail / 2, margin + tableW - rail / 2)) drawCircle(Color.White, 2.5f, Offset(x, y))
            if (labels) {
                drawContext.canvas.nativeCanvas.drawText("$i", margin / 2, y + paint.textSize / 3, paint)
                drawContext.canvas.nativeCanvas.drawText("$i", size.width - margin / 2, y + paint.textSize / 3, paint)
            }
        }
        for (pk in listOf(Pocket.TOP_LEFT, Pocket.TOP_MIDDLE, Pocket.TOP_RIGHT, Pocket.BOTTOM_LEFT, Pocket.BOTTOM_MIDDLE, Pocket.BOTTOM_RIGHT)) {
            val c = map(TablePoint(pk.x, pk.y))
            drawCircle(Color(0xFFF9D11A), ball * 0.95f, c, style = Stroke(3f))
            drawCircle(Color.White, ball * 0.8f, c)
        }
        if (exercise.spin || exercise.details.joinToString().lowercase().contains("винт")) {
            val center = Offset(fx + fw * 0.78f, fy + fh * 0.42f)
            val r = fh * 0.24f
            drawCircle(Color.White, r, center)
            for (k in listOf(0.33f, 0.66f, 1f)) drawCircle(Color.Black.copy(alpha = 0.7f), r * k, center, style = Stroke(1f))
            for (h in 0 until 12) {
                val a = h / 12.0 * 2 * Math.PI - Math.PI / 2
                drawLine(Color.Black.copy(alpha = 0.6f), center, Offset(center.x + (cos(a) * r).toFloat(), center.y + (sin(a) * r).toFloat()), 0.8f)
            }
            drawCircle(Color.Red, r * 0.2f, center)
        }
        if (labels && exercise.cueBalls.size == 1) {
            val c = map(exercise.cueBalls[0])
            val dash = PathEffect.dashPathEffect(floatArrayOf(8f, 6f))
            drawLine(Color.Black.copy(alpha = 0.75f), Offset(fx, c.y), c, 1.5f, pathEffect = dash)
            drawLine(Color.Black.copy(alpha = 0.75f), c, Offset(c.x, fy + fh), 1.5f, pathEffect = dash)
        }
        if (exercise.shot == null) exercise.cueBalls.forEachIndexed { i, cue ->
            val t = exercise.targetPoint(i) ?: return@forEachIndexed
            val from = map(cue); val to = map(t)
            drawLine(Color.Black.copy(alpha = 0.85f), from, to, 2f)
            val mid = Offset((from.x + to.x) / 2, (from.y + to.y) / 2)
            val a = atan2((to.y - from.y).toDouble(), (to.x - from.x).toDouble())
            val arrow = Path().apply {
                moveTo(mid.x + (cos(a) * 9).toFloat(), mid.y + (sin(a) * 9).toFloat())
                lineTo(mid.x + (cos(a + 2.6) * 9).toFloat(), mid.y + (sin(a + 2.6) * 9).toFloat())
                lineTo(mid.x + (cos(a - 2.6) * 9).toFloat(), mid.y + (sin(a - 2.6) * 9).toFloat()); close()
            }
            drawPath(arrow, Color.Black.copy(alpha = 0.85f))
        }
        if (exercise.rack) Exercise.rackPoints(TablePoint(45.0, 40.0)).forEach {
            drawCircle(Color(0xFFFAF2DB), ball / 2, map(it)); drawCircle(Color.Black.copy(alpha = 0.4f), ball / 2, map(it), style = Stroke(1f))
        }
        // «Чужой»/«свояк» — два белых шара, как в русском бильярде
        exercise.objectBalls.forEach {
            drawCircle(if (exercise.shot != null) Color(0xFFFAF5E6) else Color(0xFFEDB833), ball / 2, map(it))
            drawCircle(Color.Black.copy(alpha = 0.6f), ball / 2, map(it), style = Stroke(1.2f))
        }
        if (exercise.shot != null) {
            exercise.targetPoint(0)?.let { drawCircle(Color.Red, ball, map(it), style = Stroke(3f)) }
            val aim = if (showAim) exercise.aim else null
            if (aim != null) {
                val cue = map(aim.cue); val ghost = map(aim.ghost); val obj = map(aim.objectBall); val pocket = map(aim.pocket)
                val dash = PathEffect.dashPathEffect(floatArrayOf(10f, 7f))
                drawLine(Color.White.copy(alpha = 0.9f), cue, ghost, 2.4f, pathEffect = dash)
                drawCircle(Color.White, ball / 2, ghost, style = Stroke(2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 4f))))
                if (aim.kind == ShotKind.OBJECT_BALL) {
                    drawLine(Color(0xFFF9D11A), obj, pocket, 2.8f)
                } else {
                    drawLine(Color.White, ghost, pocket, 2.8f)
                    val dx = obj.x - ghost.x; val dy = obj.y - ghost.y
                    val len = maxOf(0.001f, kotlin.math.hypot(dx, dy))
                    drawLine(Color(0xFFF9D11A), obj, Offset(obj.x + dx / len * ball * 4, obj.y + dy / len * ball * 4), 2.4f, pathEffect = dash)
                }
                // Подпись сбоку: «мнимый шар» с выноской, в сторону от линии удара
                val ax = ghost.x - cue.x; val ay = ghost.y - cue.y
                val alen = maxOf(0.001f, kotlin.math.hypot(ax, ay))
                var sx = -ay / alen; var sy = ax / alen
                if (ghost.y + sy * ball * 3 < fy + ball || ghost.y + sy * ball * 3 > fy + fh - ball) { sx = -sx; sy = -sy }
                drawLine(Color.White.copy(alpha = 0.9f), Offset(ghost.x + sx * ball * 0.6f, ghost.y + sy * ball * 0.6f),
                    Offset(ghost.x + sx * ball * 2.3f, ghost.y + sy * ball * 2.3f), 1.6f)
                drawContext.canvas.nativeCanvas.drawText("мнимый шар", ghost.x + sx * ball * 3.4f, ghost.y + sy * ball * 3.4f + 5f,
                    android.graphics.Paint().apply { color = android.graphics.Color.WHITE; textSize = maxOf(16f, size.width / (if (labels) 55 else 40)); isFakeBoldText = true; textAlign = android.graphics.Paint.Align.CENTER })
            }
        }
        if (showTripod) {
            val t = exercise.tripod.first
            val c = Offset((fx + t.x / 160 * fw).toFloat().coerceIn(12f, size.width - 12f), (fy + t.y / 80 * fh).toFloat().coerceIn(12f, size.height - 12f))
            drawContext.canvas.nativeCanvas.drawText("📷", c.x, c.y + paint.textSize / 2, android.graphics.Paint().apply { textSize = size.width / 26; textAlign = android.graphics.Paint.Align.CENTER })
        }
        exercise.cueBalls.forEachIndexed { i, it ->
            drawCircle(if (exercise.yellowCue == true) Color(0xFFFAC71A) else Color.White, ball / 2, map(it))
            drawCircle(Color.Black.copy(alpha = 0.6f), ball / 2, map(it), style = Stroke(1.2f))
            if (exercise.shot != null && i == 0) drawContext.canvas.nativeCanvas.drawText("биток", map(it).x, map(it).y + ball * 1.6f,
                android.graphics.Paint().apply { color = android.graphics.Color.WHITE; textSize = maxOf(14f, size.width / (if (labels) 60 else 44)); isFakeBoldText = true; textAlign = android.graphics.Paint.Align.CENTER })
        }
    }
}

// endregion

// region Экраны

@Composable
fun ExerciseRow(app: AppState, exercise: Exercise, level: Int?, stars: Int = 0, studentId: String) {
    val p = LocalPalette.current
    GlassCard(onClick = { app.push(Route.ExerciseDetail(exercise.id, studentId)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(96.dp)) { TableScheme(exercise, labels = false) }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Secondary("№${exercise.number} · ${exercise.metric.title}", size = 12)
                Text(exercise.title, color = p.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 2)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(level?.let { "$it%" } ?: "—", fontWeight = FontWeight.Bold, color = if (level == null) p.textSecondary else p.accent)
                if (stars > 0) Text("★".repeat(stars) + "☆".repeat(3 - stars), color = Color(0xFFF5C518), fontSize = 12.sp)
            }
        }
    }
}

@Composable
fun ExercisesList(app: AppState, studentId: String) {
    val b = app.backend
    b.allExercises.groupBy { it.level }.toSortedMap().forEach { (level, list) ->
        Title(level)
        list.sortedBy { it.number }.forEach { ExerciseRow(app, it, b.exerciseLevel(studentId, it.id), b.stars(studentId, it.id), studentId) }
    }
}

@Composable
fun ExercisesScreen(app: AppState, studentId: String) {
    Screen("Упражнения", app) { ExercisesList(app, studentId) }
}

@Composable
fun ExerciseDetailScreen(app: AppState, exerciseId: String, studentId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val exercise = b.exercise(exerciseId) ?: return Screen("Упражнение", app) { Secondary("Упражнение не найдено") }
    val results = b.results(studentId, exerciseId)
    Screen("№${exercise.number}", app) {
        Text(exercise.title, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Box(Modifier.clip(RoundedCornerShape(12.dp))) { TableScheme(exercise, showTripod = true) }
        if (exercise.hasHit) GlassCard {
            Title("🎯 Куда бить по битку")
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                HitPointBall(exercise.hitX ?: 0.0, exercise.hitY ?: 0.0, 170.dp, exercise.yellowCue == true)
            }
            Text(hitDescription(exercise.hitX ?: 0.0, exercise.hitY ?: 0.0), color = p.text, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Secondary("Красная точка — место на битке, куда приходит кий", size = 12)
        }
        GlassCard {
            exercise.details.forEach { Text(it, color = p.text, fontSize = 14.sp) }
            Secondary("Точки для шаров: " + exercise.markPoints.take(6).joinToString { "${it.x.toInt()}:${it.y.toInt()}" } + if (exercise.markPoints.size > 6) "…" else "")
            Secondary("${exercise.attempts} ударов · метрика «${exercise.metric.title}»")
            Secondary("📷 " + exercise.tripod.second)
        }
        if (exercise.shot != null) AimCard(app, exercise)
        LessonCard(app, exercise)
        if (!app.isCoach && studentId == app.me) {
            PrimaryButton("📷 Камера-помощник") {
                if (b.hasSubscription(app.me)) app.push(Route.CameraTrainer(exercise.id)) else app.push(Route.Paywall(exercise.id))
            }
        }
        val videos = b.state.videos.filter { it.studentId == studentId && it.exerciseId == exerciseId }
        if (videos.isNotEmpty()) {
            Title("Видео выполнения")
            videos.forEach { v -> VideoBox(app.context, v.file, Modifier.height(220.dp)); Secondary(Fmt.stamp(v.at)) }
        }
        Title("Результаты")
        if (results.isEmpty()) Secondary("Ещё не выполнялось — тренер отметит результат после тренировки")
        results.reversed().forEach {
            Row {
                Text(Fmt.shortDay(it.at), Modifier.weight(1f), color = p.text)
                Text("${it.made} из ${it.attempts}  ", color = p.text)
                Text("${it.percent}%", fontWeight = FontWeight.Bold, color = p.accent)
            }
        }
    }
}

/** Статистика ученика для тренера и сравнение с другим учеником. */
@Composable
fun StudentStatsScreen(app: AppState, studentId: String) {
    val p = LocalPalette.current
    val b = app.backend
    var compare by remember { mutableStateOf<String?>(null) }
    Screen("Статистика", app) {
        Title("Сравнить с")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("Без сравнения", compare == null) { compare = null }
            b.students.filter { it.id != studentId }.forEach { s -> Chip(b.person(s.id)?.firstName ?: s.firstName, compare == s.id) { compare = s.id } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("● ${b.name(studentId)}", color = p.accent, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            compare?.let { Text("● ${b.name(it)}", color = p.accent2, fontWeight = FontWeight.SemiBold, fontSize = 13.sp) }
        }
        GlassCard {
            Title("Навыки")
            Metric.entries.forEach { m -> CompareRow(m.title, b.progress(studentId)[m], compare?.let { b.progress(it)[m] }, compare != null) }
        }
        GlassCard {
            Title("Упражнения, % попаданий")
            b.allExercises.forEach { e ->
                val mine = b.exerciseLevel(studentId, e.id); val other = compare?.let { b.exerciseLevel(it, e.id) }
                if (mine != null || other != null) CompareRow("№${e.number} ${e.title}", mine, other, compare != null)
            }
        }
    }
}

@Composable
private fun CompareRow(title: String, mine: Int?, other: Int?, comparing: Boolean) {
    val p = LocalPalette.current
    Column(Modifier.padding(vertical = 3.dp)) {
        Row {
            Text(title, Modifier.weight(1f), color = p.text, fontSize = 12.sp, maxLines = 1)
            Text(mine?.toString() ?: "—", color = p.accent, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            if (comparing) Text("  " + (other?.toString() ?: "—"), color = p.accent2, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        }
        Bar(mine, p.accent)
        if (comparing) Bar(other, p.accent2)
    }
}

@Composable
private fun Bar(value: Int?, color: Color) {
    val p = LocalPalette.current
    Box(Modifier.fillMaxWidth().height(6.dp).padding(top = 2.dp).background(p.textSecondary.copy(alpha = 0.15f), RoundedCornerShape(3.dp))) {
        Box(Modifier.fillMaxWidth((value ?: 0) / 100f).height(4.dp).background(color, RoundedCornerShape(3.dp)))
    }
}

/** Результаты упражнений в оценке тренировки: «забито X из N». */
@Composable
fun ExerciseResultsEditor(app: AppState, made: MutableMap<String, Int>) {
    val p = LocalPalette.current
    app.backend.allExercises.forEach { e ->
        val value = made[e.id]
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("№${e.number} ${e.title}", Modifier.weight(1f), color = p.text, fontSize = 14.sp)
                Switch(value != null, { on -> if (on) made[e.id] = e.attempts / 2 else made.remove(e.id) })
            }
            if (value != null) Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Забито $value из ${e.attempts}", Modifier.weight(1f), color = p.accent, fontWeight = FontWeight.SemiBold)
                TextButton({ if (value > 0) made[e.id] = value - 1 }) { Text("−", fontSize = 20.sp) }
                TextButton({ if (value < e.attempts) made[e.id] = value + 1 }) { Text("+", fontSize = 20.sp) }
            }
        }
    }
}

// endregion
