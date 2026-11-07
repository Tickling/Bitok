// Оформление: Ivory & Oxblood (светлая) и Midnight Chalk (тёмная), режим «Авто» — по системе.
package app.bitok.android

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

enum class Appearance(val title: String) { AUTO("Авто"), IVORY("Ivory & Oxblood"), MIDNIGHT("Midnight Chalk") }

enum class TextSize(val title: String, val scale: Float) {
    STANDARD("Стандартный", 1f), LARGE("Крупный", 1.12f), LARGER("Очень крупный", 1.25f), LARGEST("Максимальный", 1.4f)
}

data class Palette(
    val background: Color,
    val backgroundTop: Color,
    val surface: Color,
    val stroke: Color,
    val text: Color,
    val textSecondary: Color,
    val accent: Color,
    val onAccent: Color,
    val accent2: Color,
    val confirmed: Color,
    val pending: Color,
    val completed: Color,
    val cancelled: Color,
)

val Ivory = Palette(
    background = Color(0xFFF6EFE4), backgroundTop = Color(0xFFFBF6EE), surface = Color(0xCCFFFFFF), stroke = Color(0x22000000),
    text = Color(0xFF1E1A16), textSecondary = Color(0xFF7A6E62), accent = Color(0xFF7A1C2B), onAccent = Color(0xFFFFF7EF),
    accent2 = Color(0xFFB08946), confirmed = Color(0xFF2F5D8A), pending = Color(0xFFC08A1A), completed = Color(0xFF3F7D4E),
    cancelled = Color(0xFFB3261E),
)

val Midnight = Palette(
    background = Color(0xFF06122A), backgroundTop = Color(0xFF0B1E3A), surface = Color(0x1FFFFFFF), stroke = Color(0x33FFFFFF),
    text = Color(0xFFEAF0FA), textSecondary = Color(0xFF93A4C3), accent = Color(0xFF4DA3FF), onAccent = Color(0xFF06122A),
    accent2 = Color(0xFFC9A25C), confirmed = Color(0xFF4DA3FF), pending = Color(0xFFF2C14E), completed = Color(0xFF5BC489),
    cancelled = Color(0xFFFF6B6B),
)

val LocalPalette = staticCompositionLocalOf { Ivory }

@Composable
fun BitokTheme(appearance: Appearance, textSize: TextSize, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        Appearance.AUTO -> isSystemInDarkTheme()
        Appearance.IVORY -> false
        Appearance.MIDNIGHT -> true
    }
    val p = if (dark) Midnight else Ivory
    val scheme = if (dark) {
        darkColorScheme(primary = p.accent, onPrimary = p.onAccent, secondary = p.accent2, background = p.background,
            surface = p.backgroundTop, onSurface = p.text, onBackground = p.text, surfaceVariant = p.surface, error = p.cancelled)
    } else {
        lightColorScheme(primary = p.accent, onPrimary = p.onAccent, secondary = p.accent2, background = p.background,
            surface = p.backgroundTop, onSurface = p.text, onBackground = p.text, surfaceVariant = Color(0xFFEDE3D3), error = p.cancelled)
    }
    val density = LocalDensity.current
    CompositionLocalProvider(
        LocalPalette provides p,
        // Размер текста во всём приложении — независимо от настроек телефона.
        LocalDensity provides Density(density.density, density.fontScale * textSize.scale),
    ) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** Даты и цены — всегда по-русски. */
object Fmt {
    private val ru = Locale("ru", "RU")
    private fun f(pattern: String) = DateTimeFormatter.ofPattern(pattern, ru)
    private fun at(ms: Long) = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault())

    fun time(ms: Long): String = at(ms).format(f("HH:mm"))
    fun day(ms: Long): String = at(ms).format(f("EEEE, d MMMM")).replaceFirstChar { it.uppercase() }
    fun shortDay(ms: Long): String = at(ms).format(f("EE, d MMM")).replaceFirstChar { it.uppercase() }
    fun stamp(ms: Long): String = at(ms).format(f("EE, d MMM, HH:mm"))
    fun range(start: Long, minutes: Int) = "${time(start)}–${time(start + minutes * 60_000L)}"
    fun monthYear(date: java.time.LocalDate): String = date.format(f("LLLL yyyy")).replaceFirstChar { it.uppercase() }
    fun dayTitle(date: java.time.LocalDate): String = date.format(f("EEEE, d MMMM")).replaceFirstChar { it.uppercase() }
    fun rubles(value: Int): String = "%,d ₽".format(ru, value).replace(',', ' ')
}
