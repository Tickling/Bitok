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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.graphics.nativeCanvas
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
import androidx.compose.material3.Switch
import androidx.compose.ui.platform.LocalContext as LocalCtx

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

/** Изображение подарка: фото товара или 🎱 на градиенте открытки, значок открытки в углу. */
@Composable
fun GiftArt(card: GiftCard, imageId: String?, size: androidx.compose.ui.unit.Dp) {
    val context = LocalContext.current
    val photo = MediaStore.get(context, imageId)
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(size * 0.22f)).background(Brush.linearGradient(card.colors)),
            contentAlignment = Alignment.Center) {
            if (photo != null) Image(photo.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else Text("🎱", fontSize = (size.value * 0.5f).sp)
        }
        Text(card.emoji, fontSize = (size.value * 0.2f).sp,
            modifier = Modifier.align(Alignment.TopEnd).offset(x = size * 0.08f, y = -size * 0.08f).background(Color.White, RoundedCornerShape(50)).padding(3.dp))
    }
}

/** Узор фона из бильярдных значков (как фон подарков в Telegram). */
@Composable
fun GiftPattern(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val symbols = listOf("●", "★", "✦", "◎", "✧")
        val paint = android.graphics.Paint().apply { color = android.graphics.Color.argb(40, 255, 255, 255); textSize = 34f }
        var i = 0; var y = 30f
        while (y < size.height) {
            var x = if ((y / 90).toInt() % 2 == 0) 20f else 64f
            while (x < size.width) { drawContext.canvas.nativeCanvas.drawText(symbols[i % symbols.size], x, y, paint); x += 88f; i++ }
            y += 90f
        }
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
    var hideName by remember { mutableStateOf(false) }
    val name = recipient?.let { b.person(it)?.firstName } ?: "…"
    val price = listing.price?.let { Fmt.rubles(it) } ?: "договорную цену"
    Screen("Отправить подарок", app, bottom = {
        PrimaryButton(if (recipient == null) "Выберите, кому подарить" else "🎁 Отправить подарок за $price", Modifier.padding(16.dp),
            enabled = recipient != null) {
            val to = recipient ?: return@PrimaryButton
            b.sendGift(listing, app.me, to, card, message.trim(), hideName)
            app.openChat(to)
        }
    }) {
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(Brush.linearGradient(card.colors))) {
            GiftPattern(Modifier.matchParentSize())
            Column(Modifier.fillMaxWidth().padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Подарок стоимостью ${listing.price?.let { Fmt.rubles(it) } ?: "по договорённости"}", color = Color.White, fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.background(Color.Black.copy(alpha = 0.18f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 5.dp))
                Column(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.14f), RoundedCornerShape(24.dp)).padding(18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    GiftArt(card, listing.imageId, 120.dp)
                    Text("Подарок для $name", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Text("${listing.title}\nМожно показать в профиле. Забрать — у продавца на тренировке.", color = Color.White.copy(alpha = 0.9f),
                        textAlign = TextAlign.Center, fontSize = 14.sp)
                }
                OutlinedTextField(message, { message = it }, Modifier.fillMaxWidth(), placeholder = { Text("Ваше сообщение (необязательно)") },
                    shape = RoundedCornerShape(50), colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = Color.White.copy(alpha = 0.9f), unfocusedContainerColor = Color.White.copy(alpha = 0.85f),
                        focusedTextColor = Color.Black, unfocusedTextColor = Color.Black))
            }
        }
        Title("Кому")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            b.players(app.me).forEach { player ->
                Column(Modifier.clickable { recipient = player.id }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.border(3.dp, if (recipient == player.id) p.accent else Color.Transparent, RoundedCornerShape(32.dp)).padding(3.dp)) { Avatar(player, 52.dp) }
                    Text(player.firstName, fontSize = 13.sp, color = p.text, fontWeight = if (recipient == player.id) FontWeight.Bold else FontWeight.Normal)
                }
            }
        }
        Title("Открытка")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GiftCard.entries.forEach { option ->
                Text("${option.emoji} ${option.title}", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Brush.linearGradient(option.colors))
                        .border(2.dp, if (option == card) p.text else Color.Transparent, RoundedCornerShape(50))
                        .clickable { card = option }.padding(horizontal = 14.dp, vertical = 8.dp))
            }
        }
        GlassCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Скрыть моё имя", Modifier.weight(1f), color = p.text, fontSize = 16.sp)
                Switch(hideName, { hideName = it })
            }
        }
        Secondary("Вы можете скрыть имя и сообщение от всех, кто просматривает профиль $name. Скрытые имя и сообщение увидит только $name.")
    }
}

/** Сообщение о подарке в чате — как в Telegram. */
@Composable
fun GiftMessage(app: AppState, gift: Gift, isMine: Boolean) {
    val b = app.backend
    val price = gift.price?.let { Fmt.rubles(it) } ?: "—"
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(if (isMine) "Вы отправили подарок стоимостью $price" else "${b.name(gift.fromId)} отправил(а) вам подарок стоимостью $price",
            color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
            modifier = Modifier.background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 5.dp))
        Box(Modifier.width(240.dp).clip(RoundedCornerShape(22.dp)).background(Brush.verticalGradient(listOf(Color(0xFF383838), Color(0xFF1A1A1A))))) {
            GiftPattern(Modifier.matchParentSize())
            Column(Modifier.fillMaxWidth().padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                GiftArt(gift.card, b.listing(gift.listingId)?.imageId, 92.dp)
                Text(gift.itemTitle, color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Text("${gift.card.emoji} ${gift.card.title}", color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
                Text(if (isMine || gift.opened) "Посмотреть" else "Открыть", color = Color.White, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.22f))
                        .clickable { app.push(Route.GiftDetail(gift.id)) }.padding(horizontal = 20.dp, vertical = 8.dp))
            }
        }
    }
}

private fun senderName(b: DemoBackend, gift: Gift, viewer: String) =
    if (gift.hideName && viewer != gift.toId && viewer != gift.fromId) "Тайный отправитель" else b.name(gift.fromId)

/** Подарок: красивая распаковка (первый раз) и подробности — как получить, переход к товару. */
@Composable
fun GiftContent(app: AppState, gift: Gift, animated: Boolean, onDone: () -> Unit) {
    val b = app.backend
    var revealed by remember { mutableStateOf(!animated) }
    val scope = rememberCoroutineScope()
    val confetti = remember { Animatable(0f) }
    val rays by rememberInfiniteTransition(label = "rays").animateFloat(0f, 360f, infiniteRepeatable(tween(14000, easing = LinearEasing)), label = "a")
    val pieces = remember { List(90) { Triple(Random.nextFloat(), Random.nextFloat() * 0.5f, Random.nextFloat()) } }
    val colors = gift.card.colors + listOf(Color.White, Color(0xFFFFD54F))
    val isRecipient = gift.toId == app.me
    val listing = b.listing(gift.listingId)
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(gift.card.colors + Color.Black))
        .clickable(indication = null, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }) {}) {
        GiftPattern(Modifier.matchParentSize())
        Canvas(Modifier.fillMaxSize()) {
            val center = Offset(size.width / 2, size.height * 0.24f)
            rotate(rays, center) {
                for (k in 0 until 12) rotate(k * 30f, center) {
                    drawPath(androidx.compose.ui.graphics.Path().apply {
                        moveTo(center.x, center.y); lineTo(center.x - 40f, center.y - size.height); lineTo(center.x + 40f, center.y - size.height); close()
                    }, Color.White.copy(alpha = if (revealed) 0.06f else 0.12f))
                }
            }
            if (revealed) pieces.forEachIndexed { i, (x, d, spin) ->
                val t = ((confetti.value - d) / (1f - d)).coerceIn(0f, 1f)
                if (t > 0f) {
                    val px = x * size.width + (spin - 0.5f) * 120f * t; val py = -40f + (size.height + 80f) * t * t
                    rotate(spin * 900f * t, Offset(px, py)) { drawRect(colors[i % colors.size], Offset(px - 5f, py - 8f), Size(10f + spin * 8f, 16f + spin * 8f)) }
                }
            }
        }
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (!animated || revealed) {
                Row(Modifier.fillMaxWidth()) {
                    Spacer(Modifier.weight(1f))
                    TextButton(onDone) { Text("Закрыть", color = Color.White) }
                }
            } else Spacer(Modifier.height(48.dp))
            Spacer(Modifier.height(20.dp))
            Box(Modifier.clickable(enabled = !revealed) {
                revealed = true
                scope.launch { confetti.animateTo(1f, tween(3200, easing = LinearEasing)) }
            }) { GiftArt(gift.card, listing?.imageId, if (revealed) 150.dp else 190.dp) }
            if (!revealed) {
                Text("${senderName(b, gift, app.me)} прислал(а) вам подарок", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Text("Нажмите, чтобы открыть", color = Color.White.copy(alpha = 0.85f))
            } else {
                Text(if (isRecipient) "Подарок для вас" else "Подарок для ${b.name(gift.toId)}", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(gift.itemTitle, color = Color.White, fontWeight = FontWeight.SemiBold)
                Text("От: ${senderName(b, gift, app.me)} · ${Fmt.shortDay(gift.at)}" +
                    if (gift.hideName && (isRecipient || gift.fromId == app.me)) "\nИмя скрыто от других — его видите только вы" else "",
                    color = Color.White.copy(alpha = 0.9f), textAlign = TextAlign.Center, fontSize = 14.sp)
                GiftCardView(gift.card, gift.message, senderName(b, gift, app.me), gift.itemTitle, compact = true)
                Column(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.92f), RoundedCornerShape(22.dp)).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("📦 Как получить", fontWeight = FontWeight.Bold, color = Color.Black)
                    Text(b.pickupHint(gift), color = Color.Black, fontSize = 14.sp)
                    if (listing != null) TextButton({ onDone(); app.push(Route.ListingDetail(listing.id)) }) { Text("→ Перейти к товару") }
                    if (isRecipient) {
                        TextButton({ onDone(); app.openChat(gift.sellerId) }) { Text("💬 Написать продавцу") }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Показывать в профиле", Modifier.weight(1f), color = Color.Black, fontSize = 14.sp)
                            Switch(gift.showInProfile, { b.setShowInProfile(gift.id, it) })
                        }
                    }
                }
                PrimaryButton("Готово") { onDone() }
            }
        }
    }
}

@Composable
fun GiftDetailScreen(app: AppState, id: String) {
    val gift = app.backend.gift(id) ?: return Screen("Подарок", app) { Secondary("Подарок не найден") }
    GiftContent(app, gift, animated = gift.toId == app.me && !gift.opened) {
        if (gift.toId == app.me && !gift.opened) app.backend.markOpened(gift.id)
        app.pop()
    }
}

/** Неоткрытый подарок при входе — сразу распаковка. */
@Composable
fun GiftReveal(app: AppState, gift: Gift) {
    GiftContent(app, gift, animated = true) { app.backend.markOpened(gift.id) }
}

/** Подарки в профиле. */
@Composable
fun ProfileGifts(app: AppState, userId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val owner = userId == app.me
    val gifts = b.giftsOf(userId).filter { owner || it.showInProfile }
    GlassCard {
        Row { Title("Подарки"); Secondary("  ${gifts.size}") }
        if (gifts.isEmpty()) Secondary(if (owner) "Здесь появятся подарки от других игроков" else "Подарков пока нет")
        gifts.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { g ->
                    Column(Modifier.weight(1f).clickable { app.push(Route.GiftDetail(g.id)) }, horizontalAlignment = Alignment.CenterHorizontally) {
                        GiftArt(g.card, b.listing(g.listingId)?.imageId, 72.dp)
                        Text(if (g.hideName && !owner) "Тайный отправитель" else b.name(g.fromId), fontSize = 11.sp, color = p.textSecondary, maxLines = 1)
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
