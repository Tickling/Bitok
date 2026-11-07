@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// «Контент»: новости и турниры, магазин по категориям. Тренер публикует, ученик пишет продавцу.
package app.bitok.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate

private enum class ContentSegment(val title: String) { NEWS("Новости"), MARKET("Магазин") }

private val MarketCategory.emoji: String
    get() = when (this) {
        MarketCategory.CUES -> "🎱"
        MarketCategory.CHALK -> "🟦"
        MarketCategory.GLOVES -> "🧤"
        MarketCategory.ACCESSORIES -> "🎒"
        MarketCategory.REPAIR -> "🔧"
        MarketCategory.SERVICE -> "✨"
    }

private fun priceTitle(listing: Listing) = listing.price?.let { (if (listing.category.isService) "от " else "") + Fmt.rubles(it) } ?: "Договорная"

@Composable
fun ContentScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    var segment by remember { mutableStateOf(if (app.uiPage == "market") ContentSegment.MARKET else ContentSegment.NEWS) }
    var category by remember { mutableStateOf<MarketCategory?>(null) }
    Screen("Контент", app, actions = {
        if (app.isCoach) {
            IconButton({ app.push(if (segment == ContentSegment.NEWS) Route.NewsComposer else Route.ListingComposer) }) {
                Icon(Icons.Filled.AddCircle, if (segment == ContentSegment.NEWS) "Опубликовать новость" else "Добавить объявление", tint = p.accent)
            }
        }
    }) {
        Segmented(ContentSegment.entries, segment, { it.title }) { segment = it }
        when (segment) {
            ContentSegment.NEWS -> {
                if (b.state.news.isEmpty()) Secondary("Новостей пока нет")
                b.state.news.forEach { item ->
                    GlassCard {
                        Row {
                            Text(if (item.tournament) "🏆 Турнир" else "📰 Новость", Modifier.weight(1f), fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold, color = if (item.tournament) p.accent2 else p.accent)
                            Secondary(Fmt.stamp(item.at), size = 11)
                        }
                        Title(item.title)
                        item.eventAt?.let { Text("📅 ${Fmt.day(it)}, ${Fmt.time(it)}", fontWeight = FontWeight.SemiBold, color = p.text) }
                        MediaStore.get(LocalContext.current, item.imageId)?.let {
                            Image(it.asImageBitmap(), null, Modifier.fillMaxWidth().height(190.dp).clip(RoundedCornerShape(12.dp)),
                                contentScale = ContentScale.Crop)
                        }
                        Text(item.body, color = p.text)
                        item.videoUrl?.let { link ->
                            val uri = LocalUriHandler.current
                            TextButton({ runCatching { uri.openUri(link) } }) { Text("▶ Смотреть видео", fontWeight = FontWeight.SemiBold) }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Avatar(b.person(item.authorId), 22.dp)
                            Spacer(Modifier.width(6.dp))
                            Secondary(b.name(item.authorId), Modifier.weight(1f))
                            if (item.authorId == app.me) {
                                TextButton({ b.deleteNews(item.id) }) { Text("Удалить", color = p.cancelled) }
                            } else if (!app.isCoach && item.tournament) {
                                TextButton({ app.openChat(item.authorId) }) { Text("Записаться у тренера") }
                            }
                        }
                    }
                }
            }
            ContentSegment.MARKET -> {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip("Все", category == null) { category = null }
                    MarketCategory.entries.forEach { c -> Chip("${c.emoji} ${c.title}", category == c) { category = c } }
                }
                val items = b.state.listings.filter { category == null || it.category == category }
                if (items.isEmpty()) Secondary("В этой категории пока пусто")
                val goods = items.filter { !it.category.isService }
                val services = items.filter { it.category.isService }
                if (goods.isNotEmpty()) Title("Товары")
                goods.forEach { ListingRow(app, it) }
                if (services.isNotEmpty()) Title("Услуги: ремонт и обслуживание кия")
                services.forEach { ListingRow(app, it) }
            }
        }
    }
}

@Composable
private fun ListingRow(app: AppState, listing: Listing) {
    val p = LocalPalette.current
    GlassCard(onClick = { app.push(Route.ListingDetail(listing.id)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val photo = MediaStore.get(LocalContext.current, listing.imageId)
            if (photo != null) {
                Image(photo.asImageBitmap(), null, Modifier.size(56.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
            } else {
                Box(
                    Modifier.size(56.dp).background(if (listing.category.isService) p.accent2 else p.accent, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center,
                ) { Text(listing.category.emoji, fontSize = 22.sp) }
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(listing.title, fontWeight = FontWeight.SemiBold, color = p.text)
                Secondary("${listing.category.title} · ${app.backend.name(listing.sellerId)}")
            }
            Text(priceTitle(listing), fontWeight = FontWeight.Bold, color = p.accent)
        }
    }
}

@Composable
fun ListingDetailScreen(app: AppState, id: String) {
    val p = LocalPalette.current
    val b = app.backend
    val listing = b.state.listings.firstOrNull { it.id == id } ?: return Screen("Объявление", app) { Secondary("Объявление снято") }
    Screen(listing.category.title, app) {
        val photo = MediaStore.get(LocalContext.current, listing.imageId)
        if (photo != null) {
            Image(photo.asImageBitmap(), null, Modifier.fillMaxWidth().height(260.dp).clip(RoundedCornerShape(18.dp)), contentScale = ContentScale.Crop)
        } else {
            Box(
                Modifier.fillMaxWidth().height(140.dp).background(Brush.linearGradient(listOf(p.accent, p.accent2)), RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center,
            ) { Text(listing.category.emoji, fontSize = 52.sp) }
        }
        Text(listing.title, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Text(priceTitle(listing), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.accent)
        Text(listing.details, color = p.text)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(b.person(listing.sellerId), 36.dp)
            Spacer(Modifier.width(10.dp))
            Column {
                Secondary(if (listing.category.isService) "Мастер" else "Продавец")
                Title(b.name(listing.sellerId))
            }
        }
        if (listing.sellerId == app.me) {
            SecondaryButton("Снять с публикации", Modifier.fillMaxWidth(), p.cancelled) { b.deleteListing(listing.id); app.pop() }
        } else if (!app.isCoach) {
            if (!listing.category.isService) {
                PrimaryButton("🎁 Купить в подарок") { app.push(Route.GiftComposer(listing.id)) }
            }
            SecondaryButton("Написать ${if (listing.category.isService) "мастеру" else "продавцу"}", Modifier.fillMaxWidth()) {
                b.send(app.me, listing.sellerId, "Здравствуйте! Интересует «${listing.title}»")
                app.openChat(listing.sellerId)
            }
        }
    }
}

@Composable
fun NewsComposerScreen(app: AppState) {
    var tournament by remember { mutableStateOf(true) }
    var title by remember { mutableStateOf("") }
    var text by remember { mutableStateOf("") }
    var withDate by remember { mutableStateOf(true) }
    var dayOffset by remember { mutableStateOf(7) }
    var hour by remember { mutableStateOf(11) }
    var imageId by remember { mutableStateOf<String?>(null) }
    var video by remember { mutableStateOf("") }
    Screen(if (tournament) "Анонс турнира" else "Новость", app, bottom = {
        PrimaryButton("Опубликовать", Modifier.padding(16.dp), enabled = title.isNotBlank()) {
            app.backend.publish(News(newId(), app.me, tournament, title.trim(), text.trim(),
                if (withDate) LocalDate.now().plusDays(dayOffset.toLong()).at(hour) else null, System.currentTimeMillis(),
                imageId, normalizeVideo(video)))
            app.pop()
        }
    }) {
        Segmented(listOf(true, false), tournament, { if (it) "Турнир" else "Новость" }) { tournament = it }
        OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text(if (tournament) "Название турнира" else "Заголовок") })
        OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), label = { Text(if (tournament) "Формат, взнос, призы, как записаться" else "Текст") }, minLines = 4)
        Title("Фото и видео")
        PhotoField(imageId) { imageId = it }
        OutlinedTextField(video, { video = it }, Modifier.fillMaxWidth(), label = { Text("Ссылка на видео: YouTube, VK, Rutube") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), singleLine = true,
            supportingText = { if (video.isNotBlank() && normalizeVideo(video) == null) Text("Проверьте ссылку") })
        Row(verticalAlignment = Alignment.CenterVertically) {
            Title("Указать дату", Modifier.weight(1f))
            Switch(withDate, { withDate = it })
        }
        if (withDate) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (1..30).forEach { offset ->
                    val d = LocalDate.now().plusDays(offset.toLong())
                    Chip("${Venue.WEEKDAYS[d.dayOfWeek.value - 1]}\n${d.dayOfMonth}.${"%02d".format(d.monthValue)}", offset == dayOffset) { dayOffset = offset }
                }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (9..21).forEach { h -> Chip("%02d:00".format(h), h == hour) { hour = h } }
            }
        }
    }
}

@Composable
fun ListingComposerScreen(app: AppState) {
    var category by remember { mutableStateOf(MarketCategory.CUES) }
    var title by remember { mutableStateOf("") }
    var details by remember { mutableStateOf("") }
    var price by remember { mutableStateOf("") }
    var imageId by remember { mutableStateOf<String?>(null) }
    Screen("Новое объявление", app, bottom = {
        PrimaryButton("Опубликовать", Modifier.padding(16.dp), enabled = title.isNotBlank()) {
            app.backend.publish(Listing(newId(), app.me, category, title.trim(), details.trim(), price.toIntOrNull(), System.currentTimeMillis(), imageId))
            app.pop()
        }
    }) {
        Title("Категория")
        MarketCategory.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { c -> Chip("${c.emoji} ${c.title}", c == category, Modifier.weight(1f)) { category = c } }
            }
        }
        OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(),
            label = { Text(if (category.isService) "Услуга, например: замена наклейки" else "Товар, например: кий «Веста», 160 см") })
        OutlinedTextField(details, { details = it }, Modifier.fillMaxWidth(), label = { Text("Описание, состояние, сроки") }, minLines = 3)
        Title("Фото")
        PhotoField(imageId) { imageId = it }
        OutlinedTextField(price, { price = it.filter { c -> c.isDigit() } }, Modifier.fillMaxWidth(),
            label = { Text(if (category.isService) "Цена от" else "Цена") }, suffix = { Text("₽") }, placeholder = { Text("договорная") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
    }
}

/** Ссылка на видео: добавляем https://, если забыли; пустая — без видео. */
fun normalizeVideo(raw: String): String? {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return null
    val link = if (trimmed.lowercase().startsWith("http")) trimmed else "https://$trimmed"
    return link.takeIf { runCatching { java.net.URI(it).host }.getOrNull() != null }
}

/** Фото: выбрать из галереи, посмотреть, убрать. */
@Composable
fun PhotoField(imageId: String?, onChange: (String?) -> Unit) {
    val context = LocalContext.current
    val p = LocalPalette.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) onChange(MediaStore.save(context, uri))
    }
    MediaStore.get(context, imageId)?.let {
        Image(it.asImageBitmap(), null, Modifier.fillMaxWidth().height(180.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
    }
    Row {
        TextButton({ picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
            Text(if (imageId == null) "📷 Добавить фото" else "📷 Заменить фото")
        }
        if (imageId != null) TextButton({ onChange(null) }) { Text("Убрать", color = p.cancelled) }
    }
}
