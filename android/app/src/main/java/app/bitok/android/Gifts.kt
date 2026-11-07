@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Подарки: ученик покупает товар в подарок другому ученику, выбирает открытку и пишет поздравление;
// у получателя — анимация распаковки с конфетти.
package app.bitok.android

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

val GiftCard.colors: List<Color> get() = listOf(Color(from), Color(to))

@Composable
fun GiftCardView(card: GiftCard, message: String, from: String, item: String, compact: Boolean = false) {
    Column(
        Modifier.fillMaxWidth()
            .background(Brush.linearGradient(card.colors), RoundedCornerShape(if (compact) 16.dp else 24.dp))
            .border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(if (compact) 16.dp else 24.dp))
            .padding(if (compact) 12.dp else 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 10.dp),
    ) {
        Text(card.emoji, fontSize = if (compact) 30.sp else 56.sp)
        Text(card.title, color = Color.White, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, fontSize = if (compact) 17.sp else 24.sp)
        if (message.isNotBlank()) {
            Text("«$message»", color = Color.White, textAlign = TextAlign.Center, fontSize = if (compact) 13.sp else 16.sp, maxLines = if (compact) 2 else 6)
        }
        Text("🎁 $item", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = if (compact) 12.sp else 15.sp)
        Text("— $from", color = Color.White.copy(alpha = 0.85f), fontSize = if (compact) 12.sp else 15.sp)
    }
}

@Composable
fun GiftComposerScreen(app: AppState, listingId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val listing = b.state.listings.firstOrNull { it.id == listingId } ?: return Screen("Подарок", app) { Secondary("Товар снят с продажи") }
    var recipient by remember { mutableStateOf<String?>(null) }
    var card by remember { mutableStateOf(GiftCard.BIRTHDAY) }
    var message by remember { mutableStateOf("") }
    val context = LocalContext.current
    Screen("Подарок", app, bottom = {
        PrimaryButton(recipient?.let { "Подарить · ${b.person(it)?.firstName}" } ?: "Выберите, кому подарить", Modifier.padding(16.dp),
            enabled = recipient != null) {
            val to = recipient ?: return@PrimaryButton
            b.sendGift(listing, app.me, to, card, message.trim())
            app.openChat(to)
        }
    }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            MediaStore.get(context, listing.imageId)?.let {
                Image(it.asImageBitmap(), null, Modifier.size(56.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
                androidx.compose.foundation.layout.Spacer(Modifier.width(10.dp))
            }
            Column {
                Title(listing.title)
                Secondary(listing.price?.let { Fmt.rubles(it) } ?: "Цена договорная")
            }
        }
        Title("Кому")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            b.players(app.me).forEach { player ->
                Column(Modifier.clickable { recipient = player.id }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.border(3.dp, if (recipient == player.id) p.accent else Color.Transparent, RoundedCornerShape(32.dp)).padding(3.dp)) {
                        Avatar(player, 56.dp)
                    }
                    Text(player.firstName, fontSize = 13.sp, color = p.text, fontWeight = if (recipient == player.id) FontWeight.Bold else FontWeight.Normal)
                }
            }
        }
        Title("Открытка")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GiftCard.entries.forEach { option ->
                Column(
                    Modifier.size(width = 108.dp, height = 78.dp)
                        .background(Brush.linearGradient(option.colors), RoundedCornerShape(14.dp))
                        .border(3.dp, if (option == card) p.accent else Color.Transparent, RoundedCornerShape(14.dp))
                        .clickable { card = option },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(option.emoji, fontSize = 28.sp)
                    Text(option.title, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        }
        Title("Поздравление")
        OutlinedTextField(message, { message = it }, Modifier.fillMaxWidth(), minLines = 3,
            placeholder = { Text("Например: с днём рождения! Пусть каждый удар будет точным 🎱") })
        Secondary("Так увидит получатель")
        GiftCardView(card, message, b.name(app.me), listing.title)
    }
}

/** Распаковка подарка: коробка покачивается, по нажатию крышка улетает, появляется открытка и конфетти. */
@Composable
fun GiftReveal(gift: Gift, fromName: String, onClose: () -> Unit) {
    var opened by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val lid = remember { Animatable(0f) }
    val confetti = remember { Animatable(0f) }
    val wiggle by rememberInfiniteTransition(label = "wiggle")
        .animateFloat(-4f, 4f, infiniteRepeatable(tween(180, easing = LinearEasing), RepeatMode.Reverse), label = "angle")
    val pieces = remember { List(90) { Triple(Random.nextFloat(), Random.nextFloat() * 0.5f, Random.nextFloat()) } }
    val colors = gift.card.colors + listOf(Color.White, Color(0xFFFFD54F))

    Box(
        Modifier.fillMaxSize().background(Brush.radialGradient(listOf(gift.card.colors[0].copy(alpha = 0.95f), Color.Black), radius = 1400f))
            // Перехватываем нажатия, чтобы они не уходили на экран под анимацией.
            .clickable(indication = null, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }) {},
        contentAlignment = Alignment.Center,
    ) {
        if (opened) {
            Canvas(Modifier.fillMaxSize()) {
                pieces.forEachIndexed { i, (x, delayPart, spin) ->
                    val t = ((confetti.value - delayPart) / (1f - delayPart)).coerceIn(0f, 1f)
                    if (t <= 0f) return@forEachIndexed
                    val px = x * size.width + (spin - 0.5f) * 120f * t
                    val py = -40f + (size.height + 80f) * t * t
                    rotate(spin * 900f * t, Offset(px, py)) {
                        drawRect(colors[i % colors.size], Offset(px - 5f, py - 8f), Size(10f + spin * 8f, 16f + spin * 8f))
                    }
                }
            }
        }
        Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Text(if (opened) "Вам подарок!" else "$fromName прислал(а) подарок", color = Color.White, fontSize = 24.sp,
                fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Box(Modifier.height(340.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                AnimatedVisibility(opened, enter = scaleIn(spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow)) + fadeIn()) {
                    GiftCardView(gift.card, gift.message, fromName, gift.itemTitle)
                }
                if (!opened) {
                    Box(
                        Modifier.size(220.dp).rotate(if (lid.value == 0f) wiggle else 0f).scale(1f + 0.15f * lid.value)
                            .clickable {
                                scope.launch {
                                    lid.animateTo(1f, tween(550))
                                    opened = true
                                    confetti.animateTo(1f, tween(3200, easing = LinearEasing))
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        // Коробка
                        Box(Modifier.offset(y = 40.dp).size(170.dp, 140.dp).background(Brush.verticalGradient(gift.card.colors), RoundedCornerShape(14.dp))) {
                            Box(Modifier.align(Alignment.Center).width(22.dp).height(140.dp).background(Color.White.copy(alpha = 0.9f)))
                        }
                        // Крышка с бантом
                        Box(
                            Modifier.offset(y = (-50 - 210 * lid.value).dp).rotate(-35f * lid.value),
                            contentAlignment = Alignment.Center,
                        ) {
                            Box(Modifier.size(190.dp, 44.dp).background(Brush.verticalGradient(gift.card.colors.reversed()), RoundedCornerShape(10.dp))) {
                                Box(Modifier.align(Alignment.Center).width(22.dp).height(44.dp).background(Color.White.copy(alpha = 0.9f)))
                            }
                            Row(Modifier.offset(y = (-30).dp)) {
                                Box(Modifier.size(46.dp, 30.dp).rotate(-25f).background(Color.White, RoundedCornerShape(50)))
                                Box(Modifier.size(46.dp, 30.dp).rotate(25f).background(Color.White, RoundedCornerShape(50)))
                            }
                        }
                    }
                }
            }
            if (!opened) {
                Text("Нажмите на коробку, чтобы открыть", color = Color.White.copy(alpha = 0.85f))
            } else {
                PrimaryButton("Спасибо!", Modifier.padding(horizontal = 40.dp)) { onClose() }
            }
        }
    }
}

/** Карточка подарка в чате. */
@Composable
fun GiftMessage(gift: Gift, fromName: String, isMine: Boolean, onOpen: () -> Unit) {
    val p = LocalPalette.current
    Column(Modifier.width(260.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        GiftCardView(gift.card, gift.message, fromName, gift.itemTitle, compact = true)
        if (isMine) Secondary(if (gift.opened) "Получатель открыл подарок ✓" else "Ждёт, когда откроют", size = 12)
        else TextButton(onOpen) { Text(if (gift.opened) "Посмотреть ещё раз" else "Открыть подарок 🎁", color = p.accent) }
    }
}
