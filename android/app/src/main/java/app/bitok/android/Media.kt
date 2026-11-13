// Уведомления, фото товаров и новостей, редактор аватарки, смена значка приложения.
package app.bitok.android

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.util.UUID

// region Уведомления

/** Системные уведомления демо-режима и напоминания о тренировках (AlarmManager → ReminderReceiver). */
class Notifier(private val context: Context) {
    private val prefs = context.getSharedPreferences("bitok", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("notifications", true)
        set(value) = prefs.edit().putBoolean("notifications", value).apply()

    var reminderMinutes: Int
        get() = prefs.getInt("reminderMinutes", 120)
        set(value) = prefs.edit().putInt("reminderMinutes", value).apply()

    /** Режим съёмки скриншотов: уведомлений нет. */
    var silent = false

    init {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Тренировки и сообщения", NotificationManager.IMPORTANCE_HIGH))
    }

    private fun allowed() = enabled && !silent && (Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    fun post(recipient: String, title: String, body: String) {
        if (!allowed()) return
        show(context, title, "Для: $recipient · $body", (System.nanoTime() % Int.MAX_VALUE).toInt())
    }

    fun remind(booking: Booking) {
        if (!enabled || silent) return
        val at = booking.start - reminderMinutes * 60_000L
        if (at <= System.currentTimeMillis()) return
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra("title", "Тренировка через ${humanize(reminderMinutes)}")
            .putExtra("body", "${Fmt.shortDay(booking.start)}, ${Fmt.time(booking.start)} · не забудьте кий и мел 🎱")
            .putExtra("id", booking.id.hashCode())
        val pending = PendingIntent.getBroadcast(context, booking.id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
    }

    fun cancelReminder(bookingId: String) {
        val intent = Intent(context, ReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(context, bookingId.hashCode(), intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (pending != null) context.getSystemService(AlarmManager::class.java).cancel(pending)
    }

    companion object {
        const val CHANNEL = "bitok"

        fun humanize(minutes: Int) = when {
            minutes < 60 -> "$minutes мин"
            minutes == 60 -> "1 час"
            minutes == 1440 -> "1 день"
            else -> "${minutes / 60} ч"
        }

        fun show(context: Context, title: String, body: String, id: Int) {
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            runCatching { context.getSystemService(NotificationManager::class.java).notify(id, notification) }
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Notifier.show(context, intent.getStringExtra("title") ?: "Тренировка", intent.getStringExtra("body") ?: "", intent.getIntExtra("id", 1))
    }
}

// endregion

// region Фото товаров и новостей

/** Картинки на устройстве: files/media/<id>.jpg. В проде — Media Service + CDN. */
object MediaStore {
    private val cache = HashMap<String, Bitmap?>()
    private var version by mutableIntStateOf(0)

    private fun dir(context: Context) = File(context.filesDir, "media").apply { mkdirs() }

    fun get(context: Context, id: String?): Bitmap? {
        version
        if (id == null) return null
        return cache.getOrPut(id) { File(dir(context), "$id.jpg").takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) } }
    }

    fun save(context: Context, uri: Uri): String? {
        val original = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return null
        val scale = minOf(1f, 1280f / maxOf(original.width, original.height))
        val resized = Bitmap.createScaledBitmap(original, (original.width * scale).toInt(), (original.height * scale).toInt(), true)
        val id = UUID.randomUUID().toString()
        File(dir(context), "$id.jpg").outputStream().use { resized.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        cache[id] = resized
        version++
        return id
    }
}

fun loadBitmap(context: Context, uri: Uri): Bitmap? =
    context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }?.let { original ->
        val scale = minOf(1f, 2048f / maxOf(original.width, original.height))
        if (scale < 1f) Bitmap.createScaledBitmap(original, (original.width * scale).toInt(), (original.height * scale).toInt(), true) else original
    }

/**
 * Вырезает квадрат для аватарки. Картинка вписана «с заполнением» в квадрат `side`, затем увеличена в `zoom`
 * и сдвинута на (dx, dy) — те же параметры, что видит пользователь в редакторе.
 */
fun cropAvatar(source: Bitmap, side: Float, zoom: Float, dx: Float, dy: Float, out: Int = 512): Bitmap {
    val result = Bitmap.createBitmap(out, out, Bitmap.Config.ARGB_8888)
    val factor = out / side
    val fill = maxOf(side / source.width, side / source.height) * zoom * factor
    val matrix = Matrix().apply {
        postTranslate(-source.width / 2f, -source.height / 2f)
        postScale(fill, fill)
        postTranslate(out / 2f + dx * factor, out / 2f + dy * factor)
    }
    Canvas(result).drawBitmap(source, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
    return result
}

// endregion

// region Значок приложения

data class AppIconOption(val key: String, val title: String, val subtitle: String, val preview: Int)

val AppIcons = listOf(
    AppIconOption("classic", "Стеклянный биток", "Текущий значок", R.drawable.icon_preview_classic),
    AppIconOption("oxblood", "Слоновая кость", "Шар на бордо с золотым кантом", R.drawable.icon_preview_oxblood),
    AppIconOption("midnight", "Мел", "Синий мел на ночном фоне", R.drawable.icon_preview_midnight),
    AppIconOption("eight", "Восьмёрка", "Чёрный шар №8", R.drawable.icon_preview_eight),
    AppIconOption("felt", "Сукно", "Стол сверху, удар в лузу", R.drawable.icon_preview_felt),
    AppIconOption("line", "Минимализм", "Кий и шар", R.drawable.icon_preview_line),
    AppIconOption("neon", "Неон", "Светящийся контур, как в баре", R.drawable.icon_preview_neon),
    AppIconOption("gold", "Золото", "Чемпионский шар", R.drawable.icon_preview_gold),
    AppIconOption("pyramid", "Пирамида", "Треугольник шаров", R.drawable.icon_preview_pyramid),
    AppIconOption("cues", "Скрещённые кии", "Два кия и шар на сукне", R.drawable.icon_preview_cues),
    AppIconOption("rising", "Растущая пирамида", "Шары как график роста", R.drawable.icon_preview_rising),
)

/** Значки переключаются включением одного activity-alias и выключением остальных. */
object AppIconSwitcher {
    fun current(context: Context): String = context.getSharedPreferences("bitok", Context.MODE_PRIVATE).getString("appIcon", "classic")!!

    fun apply(context: Context, key: String) {
        val pm = context.packageManager
        AppIcons.forEach { option ->
            val state = if (option.key == key) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            pm.setComponentEnabledSetting(ComponentName(context, "app.bitok.android.Icon_${option.key}"), state, PackageManager.DONT_KILL_APP)
        }
        context.getSharedPreferences("bitok", Context.MODE_PRIVATE).edit().putString("appIcon", key).apply()
    }
}

// endregion
