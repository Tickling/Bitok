@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// «Биток Про»: камера-помощник. Расстановка (стол в кадре → точки → проверка шаров) и выполнение на штативе
// (подсчёт ударов, запись видео, звёзды, ошибки с советами, видео и фрагмент ошибки — тренеру).
// Сукно ищется по цвету, шары — по яркости; это демо-уровень, в проде — обученная модель.
package app.bitok.android

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore as AndroidMediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.ui.PlayerView
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.hypot

// region Анализ кадра

/** Четырёхугольник стола в долях кадра; project — точка стола (0…160 × 0…80) → точка кадра. */
data class TableQuad(val tl: Offset, val tr: Offset, val br: Offset, val bl: Offset) {
    fun project(p: TablePoint): Offset {
        val u = (p.x / 160).toFloat(); val v = (p.y / 80).toFloat()
        val top = Offset(tl.x + (tr.x - tl.x) * u, tl.y + (tr.y - tl.y) * u)
        val bottom = Offset(bl.x + (br.x - bl.x) * u, bl.y + (br.y - bl.y) * u)
        return Offset(top.x + (bottom.x - top.x) * v, top.y + (bottom.y - top.y) * v)
    }

    fun unproject(q: Offset): TablePoint {
        var u = 0.5; var v = 0.5
        repeat(8) {
            val p = project(TablePoint(u * 160, v * 80))
            val du = project(TablePoint(minOf(160.0, u * 160 + 1), v * 80)); val dv = project(TablePoint(u * 160, minOf(80.0, v * 80 + 1)))
            val a = (du.x - p.x) * 160.0; val b = (dv.x - p.x) * 80.0; val c = (du.y - p.y) * 160.0; val d = (dv.y - p.y) * 80.0
            val det = a * d - b * c
            if (abs(det) < 1e-9) return TablePoint(u * 160, v * 80)
            val ex = q.x - p.x; val ey = q.y - p.y
            u += (d * ex - b * ey) / det; v += (-c * ex + a * ey) / det
        }
        return TablePoint(u * 160, v * 80)
    }
}

/** Уменьшенный кадр: маска сукна и маска светлых (белых) шаров. */
class FrameGrid(bitmap: Bitmap, columns: Int = 120) {
    val width: Int; val height: Int
    val green: BooleanArray; val bright: BooleanArray
    init {
        val step = maxOf(1, bitmap.width / columns)
        width = bitmap.width / step; height = bitmap.height / step
        green = BooleanArray(width * height); bright = BooleanArray(width * height)
        for (y in 0 until height) for (x in 0 until width) {
            val c = bitmap.getPixel(x * step, y * step)
            val r = (c shr 16) and 0xFF; val g = (c shr 8) and 0xFF; val b = c and 0xFF
            green[y * width + x] = g > 45 && g > r * 1.18 && g > b * 1.05
            bright[y * width + x] = r + g + b > 560 && abs(r - g) < 45 && abs(g - b) < 60
        }
    }

    fun quad(): Pair<TableQuad, Double>? {
        var count = 0
        var tl = Int.MAX_VALUE to Offset.Zero; var br = Int.MIN_VALUE to Offset.Zero
        var tr = Int.MIN_VALUE to Offset.Zero; var bl = Int.MAX_VALUE to Offset.Zero
        for (y in 0 until height) for (x in 0 until width) if (green[y * width + x]) {
            count++
            val p = Offset(x.toFloat() / width, y.toFloat() / height)
            if (x + y < tl.first) tl = x + y to p
            if (x + y > br.first) br = x + y to p
            if (x - y > tr.first) tr = x - y to p
            if (x - y < bl.first) bl = x - y to p
        }
        val fraction = count.toDouble() / (width * height)
        if (fraction < 0.06) return null
        var q = TableQuad(tl.second, tr.second, br.second, bl.second)
        val top = (q.tr - q.tl).getDistance(); val left = (q.bl - q.tl).getDistance()
        if (left > top * 1.15f) q = TableQuad(q.bl, q.tl, q.tr, q.br)
        return q to fraction
    }

    fun brightBlob(near: Offset, radius: Float): Offset? {
        val cx = (near.x * width).toInt(); val cy = (near.y * height).toInt(); val r = maxOf(1, (radius * width).toInt())
        var sx = 0; var sy = 0; var n = 0
        for (y in maxOf(0, cy - r)..minOf(height - 1, cy + r)) for (x in maxOf(0, cx - r)..minOf(width - 1, cx + r)) {
            if (bright[y * width + x]) { sx += x; sy += y; n++ }
        }
        return if (n < 2) null else Offset(sx.toFloat() / n / width, sy.toFloat() / n / height)
    }
}

sealed interface Mark { data object Ok : Mark; data object Missing : Mark; data class Off(val text: String) : Mark; data object Unknown : Mark }
data class Shot(val timeSec: Double, val made: Boolean, val advice: String)

val MOTIVATION = listOf("Всё получится — каждый удар делает руку точнее", "Дыши ровно, смотри на прицел, а не на кий",
    "Чемпионы тоже мажут — главное повторять", "Ты уже лучше, чем на прошлой неделе 💪", "Спокойно: стойка, пауза, удар",
    "Ещё немного — и это упражнение станет лёгким")
private val PRAISE = listOf("Отличный удар! 🔥", "Чисто! Так держать", "Есть! Рука стабильная", "Красиво! Ещё один такой же")

fun shotAdvice(start: TablePoint, target: TablePoint, end: TablePoint): String {
    val ax = target.x - start.x; val ay = target.y - start.y; val sx = end.x - start.x; val sy = end.y - start.y
    if (hypot(sx, sy) < hypot(ax, ay) * 0.6) return "Не хватило силы: биток остановился, не дойдя до лузы. Доведите кий после удара и сделайте плавный разгон."
    return if (ax * sy - ay * sx > 0) "Биток ушёл правее лузы. Проверьте, что локоть идёт вертикально и кий не уводится в сторону; целитесь в центр лузы."
    else "Биток ушёл левее лузы. Задержите паузу перед ударом, держите голову неподвижно и не поднимайте её до конца удара."
}

/** Состояние анализа: стол, подсказка, шары, удары. Обновляется из потока анализа камеры. */
class TrainerState(val exercise: Exercise) {
    var quad by mutableStateOf<TableQuad?>(null)
    var hint by mutableStateOf("Наведите камеру на стол — нужно видеть зелёное сукно")
    var ready by mutableStateOf(false)
    val marks = mutableStateListOf<Mark>().apply { repeat(exercise.markPoints.size) { add(Mark.Unknown) } }
    val shots = mutableStateListOf<Shot>()
    var recordingStart = 0L
    var tracking = false
    private var smoothed: TableQuad? = null
    private var moving = false; private var since = 0L; private var last = Offset.Zero; private var stillSince = 0L

    fun analyze(grid: FrameGrid) {
        val found = grid.quad()
        if (found == null) { quad = null; ready = false; hint = "Наведите камеру на стол — нужно видеть зелёное сукно"; return }
        val (raw, fraction) = found
        val q = smoothed?.let { p -> fun m(a: Offset, b: Offset) = Offset(a.x * 0.7f + b.x * 0.3f, a.y * 0.7f + b.y * 0.3f)
            TableQuad(m(p.tl, raw.tl), m(p.tr, raw.tr), m(p.br, raw.br), m(p.bl, raw.bl)) } ?: raw
        smoothed = q
        val edge = 0.02f
        val touches = listOf(q.tl, q.tr, q.br, q.bl).any { it.x < edge || it.x > 1 - edge || it.y < edge || it.y > 1 - edge }
        hint = when {
            touches -> "Отойдите назад: стол не помещается в кадр целиком"
            fraction < 0.12 -> "Подойдите ближе: стол слишком маленький"
            else -> "Стол в кадре ✓ Держите телефон ровно"
        }
        ready = !touches && fraction >= 0.12
        quad = q
        val radius = maxOf(0.012f, (q.tr - q.tl).getDistance() / 160 * 3.4f)
        exercise.markPoints.forEachIndexed { i, point ->
            val projected = q.project(point)
            marks[i] = when {
                grid.brightBlob(projected, radius * 1.3f) != null -> Mark.Ok
                else -> grid.brightBlob(projected, radius * 5)?.let { nearby ->
                    val actual = q.unproject(nearby)
                    val dx = point.x - actual.x; val dy = point.y - actual.y
                    val parts = buildList {
                        if (abs(dx) > 2) add("на ${abs(dx).toInt()} см ${if (dx > 0) "к правому борту" else "к левому борту"}")
                        if (abs(dy) > 2) add("на ${abs(dy).toInt()} см ${if (dy > 0) "к нижнему борту" else "к верхнему борту"}")
                    }
                    Mark.Off(if (parts.isEmpty()) "Чуть поправьте шар на точку" else "Сдвиньте шар " + parts.joinToString(" и "))
                } ?: Mark.Missing
            }
        }
        if (tracking) track(grid, q, radius)
    }

    private fun track(grid: FrameGrid, q: TableQuad, radius: Float) {
        val start = exercise.cueBalls.firstOrNull() ?: TablePoint(70.0, 40.0)
        val target = exercise.targetPoint(0) ?: TablePoint(80.0, 0.0)
        val now = System.currentTimeMillis()
        if (!moving) {
            val atStart = grid.brightBlob(q.project(start), radius * 1.4f) != null
            if (!atStart) grid.brightBlob(q.project(start), radius * 8)?.let { moving = true; since = now; last = it; stillSince = 0 }
            return
        }
        val current = grid.brightBlob(last, radius * 6)
        if (current != null) {
            if ((current - last).getDistance() < radius * 0.15f) {
                if (stillSince == 0L) stillSince = now
                if (now - stillSince > 1000) finish(false, q.unproject(current), start, target)
            } else stillSince = 0
            last = current
        } else if (now - since > 300) {
            val end = q.unproject(last)
            finish(hypot(end.x - target.x, end.y - target.y) < 18, end, start, target)
        }
    }

    private fun finish(made: Boolean, end: TablePoint, start: TablePoint, target: TablePoint) {
        moving = false; stillSince = 0
        val t = maxOf(0.0, (System.currentTimeMillis() - recordingStart) / 1000.0 - 1.5)
        shots += Shot(t, made, if (made) PRAISE.random() else shotAdvice(start, target, end))
    }
}

// endregion

// region Экран камеры

private enum class TrainerMode(val title: String) { SETUP("Расстановка"), PERFORM("Выполнение") }
private enum class SetupPhase { FRAMING, MARKS, BALLS }

@Composable
fun CameraTrainerScreen(app: AppState, exerciseId: String) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val exercise = app.backend.exercise(exerciseId) ?: return Screen("Камера", app) { Secondary("Упражнение не найдено") }
    val state = remember { TrainerState(exercise) }
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    var mode by remember { mutableStateOf(TrainerMode.SETUP) }
    var phase by remember { mutableStateOf(SetupPhase.FRAMING) }
    var recording by remember { mutableStateOf<Recording?>(null) }
    var videoCapture by remember { mutableStateOf<VideoCapture<Recorder>?>(null) }
    var motivation by remember { mutableStateOf(MOTIVATION.first()) }
    val pulse by rememberInfiniteTransition(label = "p").animateFloat(1f, 1.25f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "s")

    if (!granted) {
        Screen("Камера-помощник", app) {
            Secondary("Нужен доступ к камере, чтобы найти стол и шары.", size = 15)
            PrimaryButton("Разрешить камеру") { permission.launch(Manifest.permission.CAMERA) }
        }
        return
    }
    val previewView = remember { PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    DisposableEffect(Unit) {
        val executor = Executors.newSingleThreadExecutor()
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888).build()
            var lastRun = 0L
            analysis.setAnalyzer(executor) { image ->
                val now = System.currentTimeMillis()
                if (now - lastRun > 150) {
                    lastRun = now
                    val bitmap = image.toBitmap()
                    val rotated = if (image.imageInfo.rotationDegrees != 0) {
                        val m = android.graphics.Matrix().apply { postRotate(image.imageInfo.rotationDegrees.toFloat()) }
                        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
                    } else bitmap
                    val grid = FrameGrid(rotated)
                    ContextCompat.getMainExecutor(context).execute { state.analyze(grid) }
                }
                image.close()
            }
            val recorder = Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.HD)).build()
            val capture = VideoCapture.withOutput(recorder)
            provider.unbindAll()
            try {
                provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis, capture)
                videoCapture = capture
            } catch (e: Exception) {
                provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            recording?.stop()
            runCatching { providerFuture.get().unbindAll() }
            executor.shutdown()
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView({ previewView }, Modifier.fillMaxSize())
        Canvas(Modifier.fillMaxSize()) {
            val q = state.quad ?: return@Canvas
            fun s(o: Offset) = Offset(o.x * size.width, o.y * size.height)
            val outline = Path().apply { moveTo(s(q.tl).x, s(q.tl).y); lineTo(s(q.tr).x, s(q.tr).y); lineTo(s(q.br).x, s(q.br).y); lineTo(s(q.bl).x, s(q.bl).y); close() }
            drawPath(outline, if (state.ready) Color.Green else Color.Yellow, style = Stroke(6f))
            if (mode == TrainerMode.SETUP && phase == SetupPhase.FRAMING) return@Canvas
            val r = maxOf(16f, (s(q.tr) - s(q.tl)).getDistance() / 160 * 3.4f) * pulse
            val first = exercise.cueBalls.firstOrNull(); val target = exercise.targetPoint(0)
            if (first != null && target != null) drawLine(Color.White.copy(alpha = 0.7f), s(q.project(first)), s(q.project(target)), 4f,
                pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(14f, 10f)))
            exercise.markPoints.forEachIndexed { i, point ->
                val color = if (phase == SetupPhase.MARKS && mode == TrainerMode.SETUP) Color.Cyan else if (state.marks.getOrNull(i) == Mark.Ok) Color.Green else Color.Red
                drawCircle(color, r, s(q.project(point)), style = Stroke(6f)); drawCircle(color, 6f, s(q.project(point)))
            }
        }
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton({ recording?.stop(); app.pop() }) { Text("✕", color = Color.White, fontSize = 22.sp) }
                Segmented(TrainerMode.entries, mode, { it.title }) { if (recording == null) mode = it }
            }
            Spacer(Modifier.weight(1f))
            Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(20.dp)).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("№${exercise.number} · ${exercise.title}", color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                if (mode == TrainerMode.SETUP) when (phase) {
                    SetupPhase.FRAMING -> {
                        Text(state.hint, color = if (state.ready) Color.Green else Color.Yellow, fontWeight = FontWeight.Bold)
                        Text("Встаньте у короткого борта так, чтобы весь стол был в кадре.", color = Color.White, fontSize = 13.sp)
                        PrimaryButton("Дальше: точки для шаров", enabled = state.ready) { phase = SetupPhase.MARKS }
                    }
                    SetupPhase.MARKS -> {
                        Text("Наклейте точки там, где светятся голубые круги", color = Color.Cyan, fontWeight = FontWeight.Bold)
                        Text(exercise.markPoints.take(6).joinToString(" · ") { "${it.x.toInt()}:${it.y.toInt()}" }, color = Color.White, fontSize = 13.sp)
                        PrimaryButton("Наклеил(а) — ставлю шары") { phase = SetupPhase.BALLS }
                    }
                    SetupPhase.BALLS -> {
                        val ok = state.marks.count { it == Mark.Ok }
                        if (ok == state.marks.size && ok > 0) {
                            Text("Всё стоит правильно! Можно бить 🎱", color = Color.Green, fontWeight = FontWeight.Bold)
                            PrimaryButton("Перейти к выполнению") { mode = TrainerMode.PERFORM }
                        } else {
                            Text("На местах: $ok из ${state.marks.size}", color = Color.White, fontWeight = FontWeight.Bold)
                            state.marks.take(4).forEachIndexed { i, m ->
                                when (m) {
                                    is Mark.Off -> Text("⚠ ${m.text}", color = Color(0xFFFFA726), fontSize = 13.sp)
                                    Mark.Missing -> Text("○ Поставьте шар на точку ${exercise.markPoints[i].x.toInt()}:${exercise.markPoints[i].y.toInt()}", color = Color.Red, fontSize = 13.sp)
                                    else -> Unit
                                }
                            }
                        }
                    }
                } else {
                    val made = state.shots.count { it.made }
                    if (recording != null) {
                        Text("● Запись · удары ${state.shots.size}/${exercise.attempts} · забито $made", color = Color.White, fontWeight = FontWeight.Bold)
                        state.shots.lastOrNull()?.let { Text(if (it.made) it.advice else "Промах. ${it.advice}", color = if (it.made) Color.Green else Color(0xFFFFA726), fontSize = 13.sp) }
                        if (state.shots.isNotEmpty()) motivation = MOTIVATION[state.shots.size % MOTIVATION.size]
                        Text(motivation, color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
                        PrimaryButton("Завершить") { recording?.stop(); recording = null; state.tracking = false }
                    } else {
                        Text("Поставьте телефон на штатив напротив себя, у противоположного борта. Камера посчитает удары и подскажет ошибки.", color = Color.White, fontSize = 13.sp)
                        Row(verticalAlignment = Alignment.Top) {
                            Box(Modifier.width(110.dp)) { TableScheme(exercise, labels = false, showTripod = true) }
                            Spacer(Modifier.width(8.dp))
                            Text(exercise.tripod.second, color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp)
                        }
                        Text(state.hint, color = if (state.ready) Color.Green else Color.Yellow, fontSize = 12.sp)
                        PrimaryButton("⏺ Начать запись", enabled = state.ready && videoCapture != null) {
                            val file = File(videosDir(context), "${newId()}.mp4")
                            state.shots.clear(); state.recordingStart = System.currentTimeMillis(); state.tracking = true
                            recording = videoCapture?.output?.prepareRecording(context, FileOutputOptions.Builder(file).build())
                                ?.start(ContextCompat.getMainExecutor(context)) { event ->
                                    if (event is VideoRecordEvent.Finalize) {
                                        app.trainingResult = TrainingResult(exercise.id, file.name, state.shots.toList(), maxOf(exercise.attempts, state.shots.size))
                                        app.push(Route.TrainingResult)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

// endregion

// region Итог

data class TrainingResult(val exerciseId: String, val file: String, val shots: List<Shot>, val attempts: Int) {
    val made get() = shots.count { it.made }
    val percent get() = if (attempts == 0) 0 else made * 100 / attempts
    /** Звёзды: 3 — от 80%, 2 — от 60%, 1 — от 40%. */
    val stars get() = when { percent >= 80 -> 3; percent >= 60 -> 2; percent >= 40 -> 1; else -> 0 }
}

@Composable
fun VideoBox(context: Context, file: String, modifier: Modifier = Modifier, seekTo: Long? = null) {
    val player = remember(file) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(Uri.fromFile(File(videosDir(context), file)))); prepare() } }
    DisposableEffect(file) { onDispose { player.release() } }
    if (seekTo != null) { player.seekTo(seekTo); player.play() }
    AndroidView({ PlayerView(it).apply { this.player = player } }, modifier.fillMaxWidth().background(Color.Black, RoundedCornerShape(12.dp)))
}

@Composable
fun TrainingResultScreen(app: AppState) {
    val p = LocalPalette.current
    val context = LocalContext.current
    val b = app.backend
    val result = app.trainingResult ?: return Screen("Результат", app) { Secondary("Нет данных") }
    val exercise = b.exercise(result.exerciseId) ?: return
    var seek by remember { mutableStateOf<Long?>(null) }
    var saved by remember { mutableStateOf(false) }
    val coach = b.coachesOf(app.me).firstOrNull()
    androidx.compose.runtime.LaunchedEffect(result) { b.recordTraining(exercise, app.me, result.made, result.attempts, result.stars) }
    Screen("Результат", app) {
        GlassCard {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("★".repeat(result.stars) + "☆".repeat(3 - result.stars), fontSize = 40.sp, color = Color(0xFFF5C518))
                Text("Забито ${result.made} из ${result.attempts} · ${result.percent}%", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.text)
                Secondary(if (result.stars >= 2) "Отлично! Упражнение засчитано ⭐️" else "Всё получится — разберём ошибки и попробуем ещё раз 💪", size = 14)
            }
        }
        VideoBox(context, result.file, Modifier.height(360.dp), seek)
        val misses = result.shots.filter { !it.made }
        if (misses.isNotEmpty()) Title("Ошибки на видео")
        misses.forEach { shot ->
            GlassCard {
                TextButton({ seek = (shot.timeSec * 1000).toLong() }) { Text("▶ Смотреть момент ${"%d:%02d".format(shot.timeSec.toInt() / 60, shot.timeSec.toInt() % 60)}") }
                Text(shot.advice, color = p.text, fontSize = 14.sp)
                if (misses.size >= 2 && coach != null) TextButton({ sendClip(app, result, exercise, shot, coach.id) }) { Text("✈ Не получается — отправить этот кусочек тренеру") }
            }
        }
        if (coach != null) PrimaryButton("Отправить видео тренеру (${coach.firstName})") {
            b.sendVideo(result.file, app.me, coach.id, "Выполнил(а) упражнение №${exercise.number}: забито ${result.made} из ${result.attempts} ${"⭐️".repeat(result.stars)}")
            app.info = "Видео отправлено тренеру в чат"
        }
        SecondaryButton("Сохранить в галерею", Modifier.fillMaxWidth()) { app.info = if (saveToGallery(context, result.file)) "Видео сохранено в галерею (Movies/Bitok)" else "Не удалось сохранить" }
        SecondaryButton(if (saved) "Сохранено в приложении ✓" else "Сохранить в приложении", Modifier.fillMaxWidth()) {
            if (!saved) { b.attachVideo(result.file, exercise.id, app.me); saved = true }
        }
        PrimaryButton("Готово") { app.pop(); app.pop() }
    }
}

private fun saveToGallery(context: Context, file: String): Boolean = runCatching {
    val values = ContentValues().apply {
        put(AndroidMediaStore.Video.Media.DISPLAY_NAME, "bitok-$file")
        put(AndroidMediaStore.Video.Media.MIME_TYPE, "video/mp4")
        put(AndroidMediaStore.Video.Media.RELATIVE_PATH, "Movies/Bitok")
    }
    val uri = context.contentResolver.insert(AndroidMediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: return false
    context.contentResolver.openOutputStream(uri)?.use { out -> File(videosDir(context), file).inputStream().use { it.copyTo(out) } }
    true
}.getOrDefault(false)

/** Фрагмент ±4 секунды вокруг ошибки (Media3 Transformer) → тренеру в чат. */
private fun sendClip(app: AppState, result: TrainingResult, exercise: Exercise, shot: Shot, coachId: String) {
    val context = app.context
    val out = File(videosDir(context), "clip-${newId()}.mp4")
    val start = maxOf(0L, (shot.timeSec * 1000).toLong() - 4000)
    val item = MediaItem.Builder().setUri(Uri.fromFile(File(videosDir(context), result.file)))
        .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionMs(start).setEndPositionMs(start + 8000).build()).build()
    val transformer = Transformer.Builder(context).addListener(object : Transformer.Listener {
        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
            app.backend.sendVideo(out.name, app.me, coachId, "Тут не получается — упражнение №${exercise.number}. ${shot.advice} Подскажите, что поправить?")
            app.info = "Фрагмент с ошибкой отправлен тренеру"
        }
        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
            app.error = "Не удалось вырезать фрагмент"
        }
    }).build()
    transformer.start(EditedMediaItem.Builder(item).build(), out.absolutePath)
}

// endregion

// region Подписка

@Composable
fun PaywallScreen(app: AppState, exerciseId: String?) {
    val p = LocalPalette.current
    val b = app.backend
    var yearly by remember { mutableStateOf(true) }
    val youth = b.hasYouthDiscount(app.me)
    Screen("Биток Про", app, bottom = {
        PrimaryButton("Оформить ${if (yearly) "на год" else "на месяц"}", Modifier.padding(16.dp)) {
            b.subscribe(app.me, if (yearly) 12 else 1)
            app.pop()
            app.pendingTrainer = exerciseId
            app.push(Route.ProWelcome)
        }
    }) {
        Text("📷", fontSize = 56.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
        GlassCard {
            listOf("Камера находит стол и подсказывает, как встать", "Показывает, куда клеить точки и ставить шары",
                "Проверяет расстановку в реальном времени и объясняет ошибки", "Режим на штативе: считает удары, звёзды за упражнение",
                "Показывает момент ошибки на видео и как исправить", "Видео и кусочек с ошибкой — тренеру в чат", "Подсказывает, где поставить штатив")
                .forEach { Text("✓ $it", color = p.text, fontSize = 15.sp) }
        }
        if (youth) Text("🎓 Вам меньше 14 лет — подписка за полцены", color = p.accent, fontWeight = FontWeight.SemiBold)
        PlanCard("Год", if (youth) "1 245 ₽" else "2 490 ₽", if (youth) "104 ₽ в месяц · скидка 50% до 14 лет" else "207 ₽ в месяц · выгода 30%", yearly) { yearly = true }
        PlanCard("Месяц", if (youth) "149 ₽" else "299 ₽", if (youth) "Скидка 50% для учеников младше 14 лет" else "Отмена в любой момент", !yearly) { yearly = false }
        if (!youth) Secondary("Ученикам младше 14 лет — скидка 50% (укажите дату рождения в профиле)")
        Secondary("Демо-режим: оплата не списывается. В Google Play — покупка через Google.")
    }
}

@Composable
private fun PlanCard(title: String, price: String, note: String, selected: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    GlassCard(Modifier.then(if (selected) Modifier.background(p.accent.copy(alpha = 0.10f), RoundedCornerShape(18.dp)) else Modifier), onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (selected) "●" else "○", color = p.accent, fontSize = 20.sp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) { Title(title); Secondary(note) }
            Text(price, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.text)
        }
    }
}

val PRO_STEPS = listOf(
    "Откройте «Прогресс» → «Упражнения» и выберите упражнение. На схеме видно, где стоят шары и где поставить штатив 📷.",
    "Нажмите «Камера-помощник» → «Расстановка». Встаньте у короткого борта: камера подскажет, отойти назад или подойти, пока весь стол не окажется в кадре.",
    "Наклейте точки там, где светятся голубые круги, и поставьте на них шары. Зелёный — шар на месте, красный — подсказка, куда сдвинуть.",
    "Режим «Выполнение»: поставьте телефон на штатив у противоположного борта, напротив себя (место показано на схеме). Нажмите «Начать запись».",
    "Бейте — приложение считает удары, хвалит за попадания и подбадривает после промахов.",
    "«Завершить» → звёзды: ⭐️ от 40%, ⭐️⭐️ от 60%, ⭐️⭐️⭐️ от 80%. Ошибки отмечены на видео с советом, как исправить.",
    "Видео можно сохранить в галерею, в приложение или отправить тренеру. Если ошибка повторяется — отправьте тренеру кусочек видео с ней.",
)

@Composable
fun ProGuide() {
    val p = LocalPalette.current
    PRO_STEPS.forEachIndexed { i, step ->
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.width(26.dp).height(26.dp).background(p.accent, RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
                Text("${i + 1}", color = p.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.width(8.dp))
            Text(step, color = p.text, fontSize = 15.sp)
        }
    }
    Secondary("Совет: хорошее освещение и однотонное сукно помогают камере. Телефон держите неподвижно.")
}

@Composable
fun ProWelcomeScreen(app: AppState) {
    Screen("Биток Про подключён ✨", app, bottom = {
        PrimaryButton("Начать", Modifier.padding(16.dp)) {
            app.pop()
            app.pendingTrainer?.let { app.push(Route.CameraTrainer(it)) }
            app.pendingTrainer = null
        }
    }) {
        Title("Как пользоваться камерой-помощником")
        ProGuide()
        Secondary("Инструкция всегда доступна в «Профиль» → «Помощь».")
    }
}

/** Карточка подписки в «Контенте» для учеников без «Биток Про». */
@Composable
fun ProPromoCard(onOpen: () -> Unit) {
    Row(Modifier.fillMaxWidth().background(androidx.compose.ui.graphics.Brush.linearGradient(listOf(Color(0xFF1F73F2), Color(0xFF732ED9))), RoundedCornerShape(20.dp))
        .clickable(onClick = onOpen).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("📷", fontSize = 30.sp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text("Биток Про", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Text("Камера расставит шары по упражнению, посчитает удары, покажет ошибки на видео и отправит их тренеру", color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp)
            Text("Узнать больше →", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        }
    }
}

// endregion
