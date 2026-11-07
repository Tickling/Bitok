// Общие элементы дизайна: фон, стеклянная карточка, аватар с фото, пилюля статуса, сетка месяца.
package app.bitok.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.io.File
import java.time.LocalDate

@Composable
fun ThemedBackground(content: @Composable () -> Unit) {
    val p = LocalPalette.current
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(p.backgroundTop, p.background)))) { content() }
}

/** «Стеклянная» карточка: вся площадь нажимается, если передан onClick. */
@Composable
fun GlassCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val p = LocalPalette.current
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(p.surface, shape)
            .border(1.dp, p.stroke, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        content = content,
    )
}

@Composable
fun Title(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = LocalPalette.current.text)
}

@Composable
fun Secondary(text: String, modifier: Modifier = Modifier, size: Int = 13) {
    Text(text, modifier, color = LocalPalette.current.textSecondary, fontSize = size.sp)
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val p = LocalPalette.current
    Button(
        onClick = onClick, enabled = enabled, modifier = modifier.fillMaxWidth().heightIn(min = 50.dp),
        shape = CircleShape, colors = ButtonDefaults.buttonColors(containerColor = p.accent, contentColor = p.onAccent),
    ) { Text(text, fontWeight = FontWeight.SemiBold, fontSize = 16.sp) }
}

@Composable
fun SecondaryButton(text: String, modifier: Modifier = Modifier, color: Color? = null, icon: ImageVector? = null, onClick: () -> Unit) {
    val p = LocalPalette.current
    OutlinedButton(onClick = onClick, modifier = modifier, shape = CircleShape) {
        if (icon != null) {
            Icon(icon, null, tint = color ?: p.accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, color = color ?: p.accent)
    }
}

@Composable
fun StatusPill(status: BookingStatus) {
    val color = statusColor(status)
    Text(
        status.title,
        color = color,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .background(color.copy(alpha = 0.14f), CircleShape)
            .border(1.dp, color.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

@Composable
fun statusColor(status: BookingStatus): Color {
    val p = LocalPalette.current
    return when (status) {
        BookingStatus.AWAITING -> p.pending
        BookingStatus.CONFIRMED -> p.confirmed
        BookingStatus.COMPLETED -> p.completed
        else -> p.cancelled
    }
}

// region Аватары

/** Фото профиля хранятся на устройстве: files/avatars/<id>.jpg. */
object AvatarStore {
    private val cache = HashMap<String, Bitmap?>()
    /** Счётчик изменений: экраны, читающие фото, перерисовываются после загрузки нового. */
    private var version by mutableIntStateOf(0)

    private fun file(context: Context, id: String) = File(File(context.filesDir, "avatars").apply { mkdirs() }, "$id.jpg")

    fun get(context: Context, id: String): Bitmap? {
        version
        if (!cache.containsKey(id)) {
            val f = file(context, id)
            cache[id] = if (f.exists()) BitmapFactory.decodeFile(f.path) else null
        }
        return cache[id]
    }

    fun set(context: Context, id: String, uri: Uri?) {
        val f = file(context, id)
        if (uri == null) {
            f.delete()
            cache[id] = null
            version++
            return
        }
        val original = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return
        val scale = minOf(1f, 512f / maxOf(original.width, original.height))
        val resized = Bitmap.createScaledBitmap(original, (original.width * scale).toInt(), (original.height * scale).toInt(), true)
        f.outputStream().use { resized.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        cache[id] = resized
        version++
    }
}

@Composable
fun Avatar(person: Person?, size: Dp = 40.dp) {
    val p = LocalPalette.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val bitmap = person?.let { AvatarStore.get(context, it.id) }
    if (bitmap != null) {
        Image(bitmap.asImageBitmap(), null, Modifier.size(size).clip(CircleShape), contentScale = ContentScale.Crop)
    } else {
        Box(
            Modifier.size(size).clip(CircleShape).background(Brush.linearGradient(listOf(p.accent, p.accent2))),
            contentAlignment = Alignment.Center,
        ) {
            Text(person?.initials ?: "?", color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.36f).sp)
        }
    }
}

// endregion

/** Сетка месяца: неделя с понедельника, доступные дни активны, точка — мои тренировки. */
@Composable
fun MonthGrid(month: LocalDate, selected: LocalDate?, available: Set<LocalDate>, marked: Set<LocalDate>, onSelect: (LocalDate) -> Unit) {
    val p = LocalPalette.current
    val first = month.withDayOfMonth(1)
    val leading = first.dayOfWeek.value - 1
    val days = (0 until month.lengthOfMonth()).map { first.plusDays(it.toLong()) }
    val cells: List<LocalDate?> = List(leading) { null } + days
    GlassCard {
        Row(Modifier.fillMaxWidth()) {
            Venue.WEEKDAYS.forEach { Text(it, Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 12.sp, color = p.textSecondary) }
        }
        cells.chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth()) {
                week.forEach { day ->
                    Box(Modifier.weight(1f).height(44.dp).padding(2.dp), contentAlignment = Alignment.Center) {
                        if (day != null) {
                            val isSelected = day == selected
                            val enabled = day in available
                            Box(
                                Modifier
                                    .fillMaxSize()
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (isSelected) p.accent else Color.Transparent)
                                    .then(if (enabled) Modifier.clickable { onSelect(day) } else Modifier),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    "${day.dayOfMonth}",
                                    color = if (isSelected) p.onAccent else p.text.copy(alpha = if (enabled) 1f else 0.35f),
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                )
                                if (day in marked) {
                                    Box(
                                        Modifier.align(Alignment.BottomCenter).padding(bottom = 4.dp).size(5.dp)
                                            .background(if (isSelected) p.onAccent else p.accent, CircleShape),
                                    )
                                }
                            }
                        }
                    }
                }
                repeat(7 - week.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
fun Chip(text: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val p = LocalPalette.current
    Text(
        text,
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) p.accent else p.textSecondary.copy(alpha = 0.12f))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        color = if (selected) p.onAccent else p.text,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
        fontSize = 14.sp,
    )
}

@Composable
fun InfoRow(icon: ImageVector, text: String) {
    val p = LocalPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = p.textSecondary, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = p.text, fontSize = 14.sp)
    }
}
