@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

// «Биток Про»: оформление профиля (фон карточки, рамки, значок PRO, статус) и карусель скриншотов в «Помощи».
package app.bitok.android

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Фон карточки игрока (кроме «Классики» — только в «Биток Про»). */
enum class CardTheme(val title: String, val colors: List<Color>) {
    CLASSIC("Классика", listOf(Color(0xFF7A1C2B), Color(0xFFB08946))),
    FELT("Сукно", listOf(Color(0xFF1F7A45), Color(0xFF0A4023))),
    NEON("Неон", listOf(Color(0xFF290A4D), Color(0xFF8C148C), Color(0xFF0D598C))),
    GOLD("Золото", listOf(Color(0xFF8C610A), Color(0xFFF2C74D), Color(0xFF734D08))),
    MARBLE("Мрамор", listOf(Color(0xFF6B707A), Color(0xFF383A45))),
    NIGHT("Ночь", listOf(Color(0xFF0A1A40), Color(0xFF1A408C))),
}

/** Рамки аватарки; isPro — только в «Биток Про». */
enum class FrameChoice(val title: String, val colors: List<Color>, val isPro: Boolean) {
    GOLD("Золотая", listOf(Color(0xFFFFF6C8), Color(0xFFF2C94C), Color(0xFFB8860B), Color(0xFFFFF6C8)), false),
    BRONZE("Бронзовая", listOf(Color(0xFFFFE0C2), Color(0xFFD08B4F), Color(0xFF8A4F1F), Color(0xFFFFE0C2)), false),
    SILVER("Серебряная", listOf(Color.White, Color(0xFFC9CED6), Color(0xFF8A929E), Color.White), true),
    GRAPHITE("Графитовая", listOf(Color(0xFF2B2F36), Color(0xFF4A505B), Color(0xFFC9A25C), Color(0xFF2B2F36)), true),
    NEON("Неоновая", listOf(Color(0xFFFF3FB4), Color(0xFF38E8FF), Color(0xFFFF3FB4)), true),
    LEGEND("Легенда", listOf(Color(0xFFFFF6C8), Color(0xFFFF8A00), Color(0xFFF2C94C), Color(0xFFFFF6C8)), true),
}

val STATUSES = listOf("", "🔥", "🎯", "🏆", "😎", "🎱", "⚡", "👑", "🍀", "💪")

fun AppState.prefs() = context.getSharedPreferences("bitok", android.content.Context.MODE_PRIVATE)
val AppState.cardTheme: CardTheme get() = if (backend.hasSubscription(me)) runCatching { CardTheme.valueOf(prefs().getString("cardTheme", "CLASSIC")!!) }.getOrDefault(CardTheme.CLASSIC) else CardTheme.CLASSIC
val AppState.frameChoice: FrameChoice get() = runCatching { FrameChoice.valueOf(prefs().getString("frame", "GOLD")!!) }.getOrDefault(FrameChoice.GOLD)
    .let { if (it.isPro && !backend.hasSubscription(me)) FrameChoice.GOLD else it }
val AppState.statusEmoji: String get() = if (backend.hasSubscription(me)) prefs().getString("status", "")!! else ""

@Composable
fun CustomizationScreen(app: AppState) {
    val p = LocalPalette.current
    val pro = app.backend.hasSubscription(app.me)
    // Перерисовка после смены настроек
    var version by androidx.compose.runtime.remember { androidx.compose.runtime.mutableIntStateOf(0) }
    version.let { }
    fun save(key: String, value: String) { app.prefs().edit().putString(key, value).apply(); version++ }
    Screen("Оформление профиля", app) {
        if (!pro) GlassCard(onClick = { app.push(Route.Paywall(null)) }) {
            Text("🔒 Фоны карточки, редкие рамки, значок PRO и статус — в «Биток Про»", color = p.accent, fontWeight = FontWeight.SemiBold)
        }
        Title("Фон карточки игрока")
        CardTheme.entries.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { t ->
                    val locked = t != CardTheme.CLASSIC && !pro
                    Box(Modifier.weight(1f).height(64.dp).clip(RoundedCornerShape(14.dp)).background(Brush.linearGradient(t.colors))
                        .border(3.dp, if (app.cardTheme == t && version >= 0) p.accent else Color.Transparent, RoundedCornerShape(14.dp))
                        .clickable { if (locked) app.push(Route.Paywall(null)) else save("cardTheme", t.name) }, contentAlignment = Alignment.Center) {
                        Text((if (locked) "🔒 " else "") + t.title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    }
                }
            }
        }
        Title("Рамка")
        FrameChoice.entries.forEach { f ->
            val locked = f.isPro && !pro
            GlassCard(onClick = { if (locked) app.push(Route.Paywall(null)) else save("frame", f.name) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(44.dp).background(Brush.sweepGradient(f.colors), RoundedCornerShape(22.dp)), contentAlignment = Alignment.Center) {
                        Avatar(app.backend.person(app.me), 36.dp)
                    }
                    Text("  ${f.title}" + if (f.isPro) "  PRO" else "", Modifier.weight(1f), color = p.text)
                    Text(if (locked) "🔒" else if (app.frameChoice == f && version >= 0) "✓" else "", color = p.accent, fontSize = 18.sp)
                }
            }
        }
        Title("Статус рядом с именем · PRO")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            STATUSES.forEach { e ->
                Chip(if (e.isEmpty()) "—" else e, app.statusEmoji == e && version >= 0) { if (pro) save("status", e) else app.push(Route.Paywall(null)) }
            }
        }
    }
}

/** Карусель скриншотов «Про» в «Помощи». */
@Composable
fun ProCarousel() {
    val p = LocalPalette.current
    val context = LocalContext.current
    val steps = listOf(
        Triple("help_pro_exercise", "1. Выберите упражнение", listOf("Схема: где стоит биток, куда бить и «часы» винта", "📷 — где поставить штатив", "«Камера-помощник» — начать")),
        Triple("help_pro_framing", "2. Весь стол в кадре", listOf("Рамка зелёная — стол найден", "Подсказка: отойти назад или подойти ближе", "«Дальше» — к точкам для шаров")),
        Triple("help_pro_marks", "3. Наклейте точки", listOf("Голубые круги — куда клеить точки", "Координаты точек по сетке стола", "«Наклеил(а)» — ставим шары")),
        Triple("help_pro_balls", "4. Проверка шаров", listOf("Зелёный — шар на месте, красный — ошибка", "Подсказка, куда сдвинуть шар", "Когда всё зелёное — к выполнению")),
        Triple("help_pro_perform", "5. Выполнение на штативе", listOf("Идёт запись, счёт ударов", "Похвала или совет после каждого удара", "Мотивация 💪 и «Завершить»")),
        Triple("help_pro_result", "6. Итог и разбор", listOf("Звёзды за упражнение", "Момент ошибки на видео и совет", "Видео — в галерею, в приложение или тренеру")),
    ).mapNotNull { (name, title, items) ->
        val id = context.resources.getIdentifier(name, "drawable", context.packageName)
        if (id == 0) null else Triple(id, title, items)
    }
    if (steps.isEmpty()) return
    val pager = rememberPagerState { steps.size }
    HorizontalPager(pager, Modifier.fillMaxWidth()) { page ->
        val (id, title, items) = steps[page]
        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Title(title)
            Image(painterResource(id), title, Modifier.fillMaxWidth().height(420.dp).clip(RoundedCornerShape(16.dp)), contentScale = ContentScale.Fit)
            items.forEachIndexed { i, t ->
                Row(verticalAlignment = Alignment.Top) {
                    Box(Modifier.size(22.dp).background(p.accent, RoundedCornerShape(11.dp)), contentAlignment = Alignment.Center) {
                        Text("${i + 1}", color = p.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                    Text("  $t", color = p.text, fontSize = 14.sp)
                }
            }
        }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
        repeat(steps.size) { i ->
            Box(Modifier.padding(3.dp).size(8.dp).background(if (pager.currentPage == i) p.accent else p.textSecondary.copy(alpha = 0.3f), RoundedCornerShape(4.dp)))
        }
    }
}
