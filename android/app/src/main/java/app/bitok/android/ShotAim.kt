// «Чужой шар» и «свояк»: мнимый шар, срез и советы; редактор схемы с лупой; видео-уроки тренера к упражнениям.
package app.bitok.android

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin

enum class ShotKind(val title: String, val metric: Metric) {
    OBJECT_BALL("Чужой шар", Metric.OBJECT_BALL),
    OWN_BALL("Свояк", Metric.OWN_BALL),
}

/** Диаметр шара в единицах схемы (как на рисунке). */
const val BALL_DIAMETER = 4.6

/** Как бить: мнимый шар — где окажется биток в момент удара. */
data class AimSolution(val ghost: TablePoint, val objectBall: TablePoint, val pocket: TablePoint, val cue: TablePoint, val cutDegrees: Int, val kind: ShotKind,
                        val hitX: Double? = null, val hitY: Double? = null) {
    /** Что даёт точка удара: накат, стоп/90°, оттяжка, боковой винт. */
    val hitAdvice: String? get() {
        val x = hitX ?: return null; val y = hitY ?: return null
        val parts = mutableListOf(when {
            y > 0.25 -> "удар выше центра — накат: после касания биток катится вперёд, угол ухода меньше 90°"
            y < -0.25 -> "удар ниже центра — оттяжка: биток после касания тянется назад"
            else -> "удар в центр — биток уходит под 90° к линии центров"
        })
        if (x > 0.25) parts += "правый винт — от борта биток отскочит правее, прицельный шар чуть уведёт влево"
        else if (x < -0.25) parts += "левый винт — от борта биток отскочит левее, прицельный шар чуть уведёт вправо"
        return "Точка удара: " + parts.joinToString("; ") + "."
    }

    val thickness: String get() = when {
        cutDegrees < 8 -> "полный шар (в лоб)"
        cutDegrees < 22 -> "≈ ¾ шара"
        cutDegrees < 38 -> "≈ ½ шара"
        cutDegrees < 55 -> "≈ ¼ шара"
        cutDegrees < 75 -> "тонко (≈ ⅛ шара)"
        else -> "очень тонко — удар на грани"
    }

    val advice: List<String> get() = baseAdvice + listOfNotNull(hitAdvice)

    private val baseAdvice: List<String> get() = when (kind) {
        ShotKind.OBJECT_BALL -> listOf(
            "Прицельтесь не в сам шар, а в центр мнимого шара (пунктир) — туда должен прийти центр битка.",
            "Срез $cutDegrees° — это $thickness. Линия «мнимый шар → чужой шар» смотрит точно в лузу.",
            if (cutDegrees > 45) "Тонкий срез: добавьте силы и держите кий ровно — малейший увод даст промах."
            else "Бейте по центру битка средним ударом, кий проводите прямо по линии прицела.",
        )
        ShotKind.OWN_BALL -> listOf(
            "Свояк: после касания биток уходит по сплошной линии в лузу, чужой шар — по жёлтому пунктиру.",
            "Прицел — центр мнимого шара, срез $cutDegrees° ($thickness).",
            when {
                (hitY ?: 0.0) > 0.25 -> "Накатом бейте мягче и доводите кий — иначе биток не докатится до лузы."
                (hitY ?: 0.0) < -0.25 -> "Оттяжке нужен резкий короткий удар и низкий мост."
                else -> "Средняя сила, кий ровно: без верхнего и нижнего винта угол ухода — ровно 90°."
            },
        )
    }
}

val Exercise.aim: AimSolution?
    get() {
        val kind = shot ?: return null
        val cue = cueBalls.firstOrNull() ?: return null
        val obj = objectBalls.firstOrNull() ?: return null
        val target = target(0) ?: return null
        val pocket = if (target == Pocket.SHORT_RAIL) TablePoint(0.0, obj.y) else TablePoint(target.x, target.y)
        val d = BALL_DIAMETER
        val dx = pocket.x - obj.x; val dy = pocket.y - obj.y
        val length = hypot(dx, dy)
        if (length <= d + 0.5) return null
        val ux = dx / length; val uy = dy / length
        val ghost = when (kind) {
            ShotKind.OBJECT_BALL -> TablePoint(obj.x - ux * d, obj.y - uy * d)
            ShotKind.OWN_BALL -> {
                // После касания биток идёт по касательной + доля нормальной скорости:
                // центр (стоп) — 0, накат — +2/7, оттяжка — −2/7. Ищем точку касания перебором вокруг шара.
                val follow = 2.0 / 7.0 * (hitY ?: 0.0).coerceIn(-1.0, 1.0)
                val best = (0 until 720).map { step ->
                    val a = step / 720.0 * 2 * Math.PI
                    val point = TablePoint(obj.x + cos(a) * d, obj.y + sin(a) * d)
                    point to ownError(cue, point, obj, pocket, follow)
                }.minBy { it.second }
                if (best.second > 0.09) return null   // ~5°: с этой точки свояк не сыграть
                best.first
            }
        }
        val vx = ghost.x - cue.x; val vy = ghost.y - cue.y
        val nx = obj.x - ghost.x; val ny = obj.y - ghost.y
        val cosine = (vx * nx + vy * ny) / maxOf(0.001, hypot(vx, vy) * hypot(nx, ny))
        val cut = Math.toDegrees(acos(cosine.coerceIn(-1.0, 1.0))).roundToInt()
        return AimSolution(ghost, obj, pocket, cue, cut, kind, hitX, hitY)
    }

/** Угол (рад) между направлением битка после касания и направлением на лузу. */
private fun ownError(cue: TablePoint, ghost: TablePoint, obj: TablePoint, pocket: TablePoint, follow: Double): Double {
    val vx = ghost.x - cue.x; val vy = ghost.y - cue.y
    val v = maxOf(0.001, hypot(vx, vy))
    val nx = (obj.x - ghost.x) / BALL_DIAMETER; val ny = (obj.y - ghost.y) / BALL_DIAMETER
    val along = (vx * nx + vy * ny) / v
    if (along <= 0.08) return Double.MAX_VALUE   // биток не попадёт в шар
    val tx = vx / v - along * nx; val ty = vy / v - along * ny
    val dx = tx + follow * along * nx; val dy = ty + follow * along * ny
    val length = hypot(dx, dy)
    if (length <= 0.02) return Double.MAX_VALUE
    val px = pocket.x - ghost.x; val py = pocket.y - ghost.y
    return acos(((dx * px + dy * py) / (length * maxOf(0.001, hypot(px, py)))).coerceIn(-1.0, 1.0))
}

/** Примеры: «чужой» и «свояк» — чтобы было видно, как работает подсказка. */
val ShotSamples = listOf(
    Exercise("shot-1", 17, "Чужой шар и свояк", "Чужой шар в правый верхний угол",
        listOf("Биток 40:40, чужой шар 120:22.", "Забить чужой шар в правую верхнюю лузу. 10 ударов."),
        Metric.OBJECT_BALL, listOf(TablePoint(40.0, 40.0)), listOf(TablePoint(120.0, 22.0)), listOf(Pocket.TOP_RIGHT), shot = ShotKind.OBJECT_BALL),
    Exercise("shot-2", 18, "Чужой шар и свояк", "Свояк в середину",
        listOf("Биток 50:55, чужой шар 85:20.", "Сыграть свояка: биток от чужого шара уходит в верхнюю среднюю лузу. 10 ударов."),
        Metric.OWN_BALL, listOf(TablePoint(50.0, 55.0)), listOf(TablePoint(85.0, 20.0)), listOf(Pocket.TOP_MIDDLE), shot = ShotKind.OWN_BALL),
    Exercise("shot-3", 19, "Чужой шар и свояк", "Резка в угол",
        listOf("Биток 60:45, чужой шар у борта 148:8.", "Тонкая резка: чужой шар в правую верхнюю лузу. Удар в центр, без винта. 10 ударов."),
        Metric.OBJECT_BALL, listOf(TablePoint(60.0, 45.0)), listOf(TablePoint(148.0, 8.0)), listOf(Pocket.TOP_RIGHT),
        shot = ShotKind.OBJECT_BALL, hitX = 0.0, hitY = 0.0),
    Exercise("shot-4", 20, "Чужой шар и свояк", "Свояк накатом (через лоб)",
        listOf("Биток 40:50, чужой шар 110:25.", "Удар выше центра: после касания биток накатом уходит в правую верхнюю лузу. 10 ударов."),
        Metric.OWN_BALL, listOf(TablePoint(40.0, 50.0)), listOf(TablePoint(110.0, 25.0)), listOf(Pocket.TOP_RIGHT),
        shot = ShotKind.OWN_BALL, hitX = 0.0, hitY = 0.7),
)

// region Редактор схемы

enum class PlaceMode(val title: String) { CUE("Биток"), OBJECT("Прицельный шар") }

/** Точка стола по нажатию; та же геометрия, что в [TableScheme]. */
fun tablePointAt(offset: Offset, size: IntSize, labels: Boolean): TablePoint? {
    val margin = if (labels) size.width * 0.05f else 0f
    val tableW = size.width - margin * 2; val tableH = size.height - margin * 2
    val rail = tableW * 0.035f
    val fx = margin + rail; val fy = margin + rail; val fw = tableW - rail * 2; val fh = tableH - rail * 2
    val x = ((offset.x - fx) / fw * 160).roundToInt().toDouble()
    val y = ((offset.y - fy) / fh * 80).roundToInt().toDouble()
    if (x !in -3.0..163.0 || y !in -3.0..83.0) return null
    return TablePoint(x.coerceIn(0.0, 160.0), y.coerceIn(0.0, 80.0))
}

fun placePoint(exercise: Exercise, mode: PlaceMode, point: TablePoint): Exercise {
    val single = exercise.shot != null
    return when (mode) {
        PlaceMode.CUE -> exercise.copy(cueBalls = if (single) listOf(point) else exercise.cueBalls + point)
        PlaceMode.OBJECT -> exercise.copy(objectBalls = if (single) listOf(point) else exercise.objectBalls + point)
    }
}

/** Стол, на котором нажатие ставит биток или прицельный шар. */
@Composable
fun EditableTable(exercise: Exercise, mode: PlaceMode, labels: Boolean, modifier: Modifier = Modifier, onChange: (Exercise, PlaceMode) -> Unit) {
    Box(modifier
        .pointerInput(exercise, mode, labels) {
            detectTapGestures { offset ->
                val point = tablePointAt(offset, this.size, labels) ?: return@detectTapGestures
                val next = placePoint(exercise, mode, point)
                // После битка для «чужого»/«свояка» сразу ставим прицельный шар
                val nextMode = if (exercise.shot != null && mode == PlaceMode.CUE) PlaceMode.OBJECT else mode
                onChange(next, nextMode)
            }
        }) {
        TableScheme(exercise, labels = labels, showAim = true)
    }
}

/** Лупа: стол во весь экран, повёрнут вдоль экрана; повторное нажатие на лупу возвращает назад. */
@Composable
fun SchemeMagnifier(exercise: Exercise, mode: PlaceMode, onChange: (Exercise, PlaceMode) -> Unit, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Color.White).padding(vertical = 8.dp)) {
            Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PlaceMode.entries.forEach { m -> Chip(m.title, m == mode, Modifier.weight(1f)) { onChange(exercise, m) } }
                IconButton(onClose) { Icon(Icons.Filled.ZoomOut, "Уменьшить и вернуться", tint = Color.Black) }
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                val long = minOf(maxHeight, maxWidth * 1.95f)
                val short = long / 1.95f
                EditableTable(exercise, mode, labels = true,
                    modifier = Modifier.requiredSize(long, short).graphicsLayer { rotationZ = 90f }, onChange = onChange)
            }
            Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(pointsSummary(exercise), Modifier.weight(1f), color = Color.Black, fontSize = 12.sp, maxLines = 2)
                TextButton({ onChange(undoPoint(exercise, mode), mode) }) { Text("Отменить точку") }
            }
        }
    }
}

fun undoPoint(exercise: Exercise, mode: PlaceMode): Exercise = when {
    mode == PlaceMode.OBJECT && exercise.objectBalls.isNotEmpty() -> exercise.copy(objectBalls = exercise.objectBalls.dropLast(1))
    exercise.cueBalls.isNotEmpty() -> exercise.copy(cueBalls = exercise.cueBalls.dropLast(1))
    else -> exercise
}

fun pointsSummary(exercise: Exercise): String {
    val parts = mutableListOf("Биток: " + exercise.cueBalls.joinToString { "${it.x.toInt()}:${it.y.toInt()}" })
    if (exercise.objectBalls.isNotEmpty()) parts += "шар: " + exercise.objectBalls.joinToString { "${it.x.toInt()}:${it.y.toInt()}" }
    exercise.aim?.let { parts += "мнимый ${it.ghost.x.toInt()}:${it.ghost.y.toInt()}, срез ${it.cutDegrees}°" }
    return parts.joinToString(" · ")
}

/** Ручное упражнение: тип удара, точки нажатием на стол, лупа, луза, метрика, видео-урок. */
@Composable
fun ManualExerciseEditor(app: AppState, onSave: (Exercise) -> Unit) {
    val id = remember { "custom-${newId().take(8)}" }
    var title by remember { mutableStateOf("") }
    var details by remember { mutableStateOf("") }
    var exercise by remember {
        mutableStateOf(Exercise(id, app.backend.allExercises.size + 1, "Мои упражнения", "", emptyList(), Metric.AIMING,
            listOf(TablePoint(70.0, 40.0)), targets = listOf(Pocket.TOP_MIDDLE), importedBy = app.me))
    }
    var mode by remember { mutableStateOf(PlaceMode.CUE) }
    var magnified by remember { mutableStateOf(false) }
    val change: (Exercise, PlaceMode) -> Unit = { e, m -> exercise = e; mode = m }
    GlassCard {
        OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("Название") })
        OutlinedTextField(details, { details = it }, Modifier.fillMaxWidth(), label = { Text("Описание: винт, сколько ударов, на что обратить внимание") }, minLines = 2)
        Secondary("Удар", size = 13)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip("В лузу", exercise.shot == null, Modifier.weight(1f)) { exercise = exercise.copy(shot = null) }
            ShotKind.entries.forEach { kind ->
                Chip(kind.title, exercise.shot == kind, Modifier.weight(1f)) {
                    exercise = exercise.copy(shot = kind, metric = kind.metric, cueBalls = exercise.cueBalls.take(1),
                        objectBalls = exercise.objectBalls.take(1).ifEmpty { listOf(TablePoint(110.0, 25.0)) },
                        targets = if (exercise.targets.firstOrNull() == Pocket.SHORT_RAIL) listOf(Pocket.TOP_RIGHT) else exercise.targets)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            PlaceMode.entries.forEach { m -> Chip("Ставим: ${m.title.lowercase()}", m == mode, Modifier.weight(1f)) { mode = m } }
        }
        Box {
            EditableTable(exercise, mode, labels = false, modifier = Modifier.clip(RoundedCornerShape(8.dp)), onChange = change)
            IconButton({ magnified = true }, Modifier.align(Alignment.TopEnd).padding(4.dp).size(40.dp).background(Color.White.copy(alpha = 0.8f), CircleShape)) {
                Icon(Icons.Filled.ZoomIn, "Открыть стол крупно", tint = Color.Black)
            }
        }
        Secondary(pointsSummary(exercise), size = 12)
        val aim = exercise.aim
        if (aim != null) Secondary("🎯 Срез ${aim.cutDegrees}° · ${aim.thickness}", size = 13)
        else if (exercise.shot != null) Text("Поставьте прицельный шар подальше от лузы", color = Color(0xFFE08A00), fontSize = 13.sp)
        TextButton({ exercise = undoPoint(exercise, mode) }) { Text("Убрать последнюю точку") }
        Secondary("Луза", size = 13)
        val pockets = listOf(Pocket.TOP_LEFT to "Верх Л", Pocket.TOP_MIDDLE to "Верх С", Pocket.TOP_RIGHT to "Верх П",
            Pocket.BOTTOM_LEFT to "Низ Л", Pocket.BOTTOM_MIDDLE to "Низ С", Pocket.BOTTOM_RIGHT to "Низ П")
        pockets.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { (pk, t) -> Chip(t, exercise.targets.firstOrNull() == pk, Modifier.weight(1f)) { exercise = exercise.copy(targets = listOf(pk)) } }
            }
        }
        if (exercise.shot == null) Chip("Короткий борт", exercise.targets.firstOrNull() == Pocket.SHORT_RAIL) { exercise = exercise.copy(targets = listOf(Pocket.SHORT_RAIL)) }
        Secondary("Метрика", size = 13)
        Metric.entries.chunked(4).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { m -> Chip(m.short, m == exercise.metric, Modifier.weight(1f)) { exercise = exercise.copy(metric = m) } }
                repeat(4 - row.size) { androidx.compose.foundation.layout.Spacer(Modifier.weight(1f)) }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Биток жёлтый (цветной)", Modifier.weight(1f), color = LocalPalette.current.text)
            androidx.compose.material3.Switch(exercise.yellowCue == true, { exercise = exercise.copy(yellowCue = if (it) true else null) })
        }
        Title("Камера-помощник")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Допуск у лузы: ${exercise.toleranceCm ?: 6} см", Modifier.weight(1f), color = LocalPalette.current.text)
            TextButton({ exercise = exercise.copy(toleranceCm = ((exercise.toleranceCm ?: 6) - 1).coerceAtLeast(2)) }) { Text("−") }
            TextButton({ exercise = exercise.copy(toleranceCm = ((exercise.toleranceCm ?: 6) + 1).coerceAtMost(15)) }) { Text("+") }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Цель серии: ${exercise.goalPercent ?: 70}%", Modifier.weight(1f), color = LocalPalette.current.text)
            TextButton({ exercise = exercise.copy(goalPercent = ((exercise.goalPercent ?: 70) - 10).coerceAtLeast(30)) }) { Text("−") }
            TextButton({ exercise = exercise.copy(goalPercent = ((exercise.goalPercent ?: 70) + 10).coerceAtMost(100)) }) { Text("+") }
        }
        Secondary("Допуск — ширина зелёного «коридора» в кадре: насколько шар может уйти от центра лузы. Цель — сколько процентов забить за серию.", size = 12)
        Title("Точка удара по битку")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Указать точку удара", Modifier.weight(1f), color = LocalPalette.current.text)
            androidx.compose.material3.Switch(exercise.hasHit, { on ->
                exercise = exercise.copy(hitX = if (on) 0.0 else null, hitY = if (on) 0.0 else null)
            })
        }
        if (exercise.hasHit) {
            HitPointPicker(exercise.hitX ?: 0.0, exercise.hitY ?: 0.0, exercise.yellowCue == true) { hx, hy ->
                exercise = exercise.copy(hitX = hx, hitY = hy)
            }
            if (exercise.shot == ShotKind.OWN_BALL) Secondary("Для свояка точка удара меняет траекторию: мнимый шар пересчитается.", size = 12)
        }
        Title("Видео-урок")
        LessonVideoPicker(app, id)
        PrimaryButton("Сохранить", enabled = title.isNotBlank() && exercise.cueBalls.isNotEmpty() && (exercise.shot == null || exercise.aim != null)) {
            onSave(exercise.copy(title = title.trim(), details = details.lines().filter { it.isNotBlank() }))
        }
    }
    if (magnified) SchemeMagnifier(exercise, mode, change) { magnified = false }
}

// endregion

// region Видео-уроки

fun DemoBackend.lessonVideo(exerciseId: String) = state.exerciseLessons[exerciseId]

fun DemoBackend.setLesson(exerciseId: String, file: String?, coachId: String) {
    update { it.copy(exerciseLessons = if (file == null) it.exerciseLessons - exerciseId else it.exerciseLessons + (exerciseId to file)) }
    if (file == null) return
    val title = exercise(exerciseId)?.let { "№${it.number} «${it.title}»" } ?: "Новое упражнение"
    students.filter { s -> coachesOf(s.id).any { it.id == coachId } }.forEach {
        notify(it.id, "🎬 Видео-урок от тренера", "$title — как выполнять и на что обратить внимание")
    }
}

private fun copyVideo(context: Context, uri: Uri): String? = runCatching {
    val name = "lesson-${newId().take(8)}.mp4"
    context.contentResolver.openInputStream(uri)?.use { input -> File(videosDir(context), name).outputStream().use { input.copyTo(it) } } ?: return null
    name
}.getOrNull()

/** Тренер: добавить, заменить или убрать видео-урок к упражнению. */
@Composable
fun LessonVideoPicker(app: AppState, exerciseId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val b = app.backend
    var loading by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        loading = true
        scope.launch {
            val name = withContext(Dispatchers.IO) { copyVideo(context, uri) }
            loading = false
            if (name != null) { b.setLesson(exerciseId, name, app.me); app.info = "Видео-урок добавлен" } else app.error = "Не удалось загрузить видео"
        }
    }
    val file = b.lessonVideo(exerciseId)
    if (file != null) VideoBox(context, file, Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(12.dp)))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        SecondaryButton(if (loading) "Загружаю…" else if (file == null) "🎬 Добавить видео-урок" else "Заменить видео") {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
        }
        if (file != null) SecondaryButton("Убрать", color = Color(0xFFD32F2F)) { b.setLesson(exerciseId, null, app.me) }
    }
    Secondary("Расскажите, как выполнять упражнение и на что обратить внимание. Ученики увидят урок в упражнении.", size = 12)
}

// endregion

// region Карточки в упражнении

private fun isPro(app: AppState) = app.isCoach || app.backend.hasSubscription(app.me)

/** «Как бить» для чужого шара и свояка (Pro). */
@Composable
fun AimCard(app: AppState, exercise: Exercise) {
    val p = LocalPalette.current
    GlassCard {
        Title("🎯 Как бить: ${exercise.shot?.title?.lowercase()}")
        val aim = exercise.aim
        if (isPro(app) && aim != null) {
            Box(Modifier.clip(RoundedCornerShape(10.dp))) { TableScheme(exercise, showAim = true) }
            Text("Срез ${aim.cutDegrees}° · ${aim.thickness}", color = p.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            aim.advice.forEach { Text("✓ $it", color = p.text, fontSize = 14.sp) }
            Secondary("Пунктирный круг — мнимый шар: в этой точке должен оказаться центр битка в момент удара.", size = 12)
        } else {
            Secondary("В Pro приложение рисует мнимый шар, показывает срез и толщину и объясняет, как сыграть ${if (exercise.shot == ShotKind.OWN_BALL) "свояка" else "чужой шар"}.", size = 14)
            SecondaryButton("🔓 Открыть в Pro") { app.push(Route.Paywall(null)) }
        }
    }
}

/** Видео-урок тренера: ученик с Pro смотрит, тренер добавляет. */
@Composable
fun LessonCard(app: AppState, exercise: Exercise) {
    val p = LocalPalette.current
    val file = app.backend.lessonVideo(exercise.id)
    if (app.isCoach) {
        GlassCard { Title("🎬 Видео-урок"); LessonVideoPicker(app, exercise.id) }
    } else if (file != null) {
        GlassCard {
            Title("🎬 Видео-урок тренера")
            if (isPro(app)) {
                VideoBox(LocalContext.current, file, Modifier.fillMaxWidth().height(220.dp).clip(RoundedCornerShape(12.dp)))
                Text("Тренер рассказывает, как выполнять упражнение и на что обратить внимание.", color = p.textSecondary, fontSize = 12.sp)
            } else {
                Secondary("Тренер записал видео: как выполнять упражнение и на что обратить внимание. Доступно в Pro.", size = 14)
                SecondaryButton("🔓 Смотреть в Pro") { app.push(Route.Paywall(null)) }
            }
        }
    }
}

// endregion


// region Точка удара по битку

fun hitDescription(x: Double, y: Double): String {
    val vertical = if (y > 0.25) "выше центра" else if (y < -0.25) "ниже центра" else "по центру"
    val side = if (x > 0.25) ", правый винт" else if (x < -0.25) ", левый винт" else ""
    return "Точка удара: $vertical$side"
}

/** Отдельная картинка «биток»: шар крупно, сетка (кольца и крест) и красная точка — куда бить кием. */
@Composable
fun HitPointBall(x: Double, y: Double, size: androidx.compose.ui.unit.Dp, yellow: Boolean = false, modifier: Modifier = Modifier) {
    androidx.compose.foundation.Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2
        val c = Offset(this.size.width / 2, this.size.height / 2)
        val light = if (yellow) Color(0xFFFFE15A) else Color(0xFFFFFDF5)
        val dark = if (yellow) Color(0xFFD99E0D) else Color(0xFFCCC4B3)
        drawCircle(Color.Black.copy(alpha = 0.18f), r, c + Offset(r * 0.06f, r * 0.08f))
        drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(listOf(light, dark), center = c - Offset(r * 0.35f, r * 0.4f), radius = r * 1.6f), r, c)
        val grid = Color.Red.copy(alpha = 0.55f)
        listOf(0.33f, 0.66f, 0.97f).forEach { drawCircle(grid, r * it, c, style = androidx.compose.ui.graphics.drawscope.Stroke(2f)) }
        drawLine(grid, Offset(c.x - r, c.y), Offset(c.x + r, c.y), 2f)
        drawLine(grid, Offset(c.x, c.y - r), Offset(c.x, c.y + r), 2f)
        drawCircle(Color.Red, r * 0.13f, Offset(c.x + (x * r * 0.8).toFloat(), c.y - (y * r * 0.8).toFloat()))
    }
}

/** Выбор точки удара: нажмите или проведите по шару. */
@Composable
fun HitPointPicker(x: Double, y: Double, yellow: Boolean, onChange: (Double, Double) -> Unit) {
    val p = LocalPalette.current
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Secondary("Нажмите на шар — куда бить кием", size = 12)
        Box(Modifier.size(160.dp).pointerInput(Unit) {
            fun set(o: Offset) {
                val r = this.size.width / 2f * 0.8f
                var nx = (o.x - this.size.width / 2f) / r; var ny = -(o.y - this.size.height / 2f) / r
                val len = kotlin.math.hypot(nx, ny)
                if (len > 1) { nx /= len; ny /= len }
                onChange(Math.round(nx * 4) / 4.0, Math.round(ny * 4) / 4.0)
            }
            detectDragGestures(onDragStart = { set(it) }) { change, _ -> set(change.position) }
        }.pointerInput(Unit) { detectTapGestures { o ->
            val r = this.size.width / 2f * 0.8f
            var nx = (o.x - this.size.width / 2f) / r; var ny = -(o.y - this.size.height / 2f) / r
            val len = kotlin.math.hypot(nx, ny)
            if (len > 1) { nx /= len; ny /= len }
            onChange(Math.round(nx * 4) / 4.0, Math.round(ny * 4) / 4.0)
        } }) { HitPointBall(x, y, 160.dp, yellow) }
        Text(hitDescription(x, y), color = p.text, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip("Верх", y > 0.25 && kotlin.math.abs(x) <= 0.25) { onChange(0.0, 0.75) }
            Chip("Центр", kotlin.math.abs(y) <= 0.25 && kotlin.math.abs(x) <= 0.25) { onChange(0.0, 0.0) }
            Chip("Низ", y < -0.25 && kotlin.math.abs(x) <= 0.25) { onChange(0.0, -0.75) }
        }
        Secondary("Верх — накат, центр — уход 90°, низ — оттяжка", size = 12)
    }
}

// endregion


// region Зона камеры

/** Прямоугольник на столе в сантиметрах схемы (x 0…160, y 0…80). */
data class CameraZone(val minX: Double, val minY: Double, val width: Double, val height: Double)

/** Зона стола, которую обязательно должна видеть камера: шары, луза, мнимый шар и запас. null — нужен весь стол. */
val Exercise.cameraZone: CameraZone?
    get() {
        val points = markPoints.toMutableList()
        cueBalls.indices.forEach { i -> targetPoint(i)?.let { points += it } }
        aim?.let { points += it.ghost; points += it.pocket }
        if (points.isEmpty()) return null
        val pad = 12.0
        var minX = maxOf(0.0, points.minOf { it.x } - pad); var maxX = minOf(160.0, points.maxOf { it.x } + pad)
        var minY = maxOf(0.0, points.minOf { it.y } - pad); var maxY = minOf(80.0, points.maxOf { it.y } + pad)
        // Не меньше 50×36, чтобы в кадре было за что «зацепиться»
        if (maxX - minX < 50) { val c = (minX + maxX) / 2; minX = (c - 25).coerceIn(0.0, 110.0); maxX = minX + 50 }
        if (maxY - minY < 36) { val c = (minY + maxY) / 2; minY = (c - 18).coerceIn(0.0, 44.0); maxY = minY + 36 }
        // Округляем до отметок на бортах (каждые 10)
        minX = Math.floor(minX / 10) * 10; maxX = minOf(160.0, Math.ceil(maxX / 10) * 10)
        minY = Math.floor(minY / 10) * 10; maxY = minOf(80.0, Math.ceil(maxY / 10) * 10)
        val zone = CameraZone(minX, minY, maxX - minX, maxY - minY)
        return if (zone.width * zone.height > 160 * 80 * 0.8) null else zone
    }

/** Словами, по отметкам на бортах. */
val Exercise.cameraZoneText: String
    get() {
        val z = cameraZone ?: return "Камера должна видеть весь стол."
        val long = if (z.width >= 160) "весь длинный борт" else "длинный борт от отметки ${z.minX.toInt()} до ${(z.minX + z.width).toInt()}"
        val short = if (z.height >= 80) "весь короткий борт" else "короткий борт от ${z.minY.toInt()} до ${(z.minY + z.height).toInt()}"
        return "Если стол не помещается в кадр, достаточно зоны упражнения: $long, $short. Края кадра — по границам зоны."
    }

// endregion
