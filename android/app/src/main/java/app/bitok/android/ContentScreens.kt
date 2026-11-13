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
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
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
        if (!app.isCoach && !b.hasSubscription(app.me)) ProPromoCard { app.push(Route.Paywall(null)) }
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
        val context = LocalContext.current
        val photos = listing.allImageIds.mapNotNull { MediaStore.get(context, it) }
        if (photos.isNotEmpty()) {
            val pager = androidx.compose.foundation.pager.rememberPagerState { photos.size }
            androidx.compose.foundation.pager.HorizontalPager(pager, Modifier.fillMaxWidth().height(260.dp).clip(RoundedCornerShape(18.dp))) { page ->
                Image(photos[page].asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            }
            if (photos.size > 1) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    repeat(photos.size) { i ->
                        Box(Modifier.padding(3.dp).size(7.dp).background(if (i == pager.currentPage) p.accent else p.textSecondary.copy(alpha = 0.35f), RoundedCornerShape(50)))
                    }
                }
            }
        } else {
            Box(
                Modifier.fillMaxWidth().height(140.dp).background(Brush.linearGradient(listOf(p.accent, p.accent2)), RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center,
            ) { Text(listing.category.emoji, fontSize = 52.sp) }
        }
        Text(listing.title, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Text(priceTitle(listing), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.accent)
        Text(listing.details, color = p.text)
        if (listing.specs.isNotEmpty()) GlassCard {
            Title("Характеристики")
            listing.specs.forEach { spec ->
                Row(Modifier.padding(vertical = 4.dp)) {
                    Text(spec.name, Modifier.weight(1f), color = p.textSecondary, fontSize = 15.sp)
                    Text(spec.value, color = p.text, fontSize = 15.sp)
                }
            }
        }
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
    val p = LocalPalette.current
    var category by remember { mutableStateOf(MarketCategory.CUES) }
    var title by remember { mutableStateOf("") }
    var details by remember { mutableStateOf("") }
    var price by remember { mutableStateOf("") }
    var images by remember { mutableStateOf(listOf<String>()) }
    var specs by remember { mutableStateOf(listOf<ListingSpec>()) }
    val missing = buildList {
        if (!category.isService && images.isEmpty()) add("фото")
        if (title.isBlank()) add("название")
        if (details.isBlank()) add("описание")
    }
    Screen("Новое объявление", app, bottom = {
        PrimaryButton("Опубликовать", Modifier.padding(16.dp), enabled = missing.isEmpty()) {
            app.backend.publish(Listing(newId(), app.me, category, title.trim(), details.trim(), price.toIntOrNull(), System.currentTimeMillis(),
                images.firstOrNull(), images.drop(1), specs.filter { it.name.isNotBlank() && it.value.isNotBlank() }))
            app.pop()
        }
    }) {
        RequiredTitle("Категория")
        MarketCategory.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { c -> Chip("${c.emoji} ${c.title}", c == category, Modifier.weight(1f)) { category = c } }
            }
        }
        RequiredTitle("Фото", required = !category.isService)
        MultiPhotoField(images, 10) { images = it }
        OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(),
            label = { Text((if (category.isService) "Услуга, например: замена наклейки" else "Товар, например: кий «Веста», 160 см") + " *") })
        OutlinedTextField(details, { details = it }, Modifier.fillMaxWidth(), label = { Text("Описание: состояние, история, комплект *") }, minLines = 3)
        OutlinedTextField(price, { price = it.filter { c -> c.isDigit() }.trimStart('0').take(9) }, Modifier.fillMaxWidth(),
            label = { Text(if (category.isService) "Цена от" else "Цена") }, suffix = { Text("₽") }, placeholder = { Text("договорная") },
            visualTransformation = ThousandsMask,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
        Title("Характеристики")
        Secondary("Например: длина, вес, материал — покупатель увидит их таблицей.", size = 13)
        specs.forEachIndexed { index, spec ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(spec.name, { v -> specs = specs.toMutableList().also { it[index] = spec.copy(name = v) } }, Modifier.weight(0.42f),
                    label = { Text("Название") }, singleLine = true)
                OutlinedTextField(spec.value, { v -> specs = specs.toMutableList().also { it[index] = spec.copy(value = v) } }, Modifier.weight(0.58f),
                    label = { Text("Значение") }, singleLine = true)
                TextButton({ specs = specs.toMutableList().also { it.removeAt(index) } }) { Text("✕", color = p.cancelled) }
            }
        }
        val unused = category.suggestedSpecs.filter { name -> specs.none { it.name == name } }
        if (unused.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                unused.forEach { name -> Chip("+ $name", false) { specs = specs + ListingSpec(name, "") } }
            }
        }
        TextButton({ specs = specs + ListingSpec("", "") }) { Text("+ Своя характеристика") }
        if (missing.isEmpty()) Text("✓ Всё заполнено — можно публиковать", color = Color(0xFF2E7D32), fontSize = 14.sp)
        else Text("Заполните: " + missing.joinToString(), color = p.cancelled, fontSize = 14.sp)
        Secondary("* — обязательные поля", size = 12)
    }
}

/** Заголовок поля; обязательное — со звёздочкой. */
@Composable
fun RequiredTitle(text: String, required: Boolean = true) {
    val p = LocalPalette.current
    Row {
        Title(text)
        if (required) Text(" *", color = p.cancelled, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Цена с разрядами: «18600» показывается как «18 600». */
object ThousandsMask : androidx.compose.ui.text.input.VisualTransformation {
    override fun filter(text: androidx.compose.ui.text.AnnotatedString): androidx.compose.ui.text.input.TransformedText {
        val d = text.text
        val out = StringBuilder()
        d.forEachIndexed { i, c -> if (i > 0 && (d.length - i) % 3 == 0) out.append(' '); out.append(c) }
        fun spacesBefore(offset: Int) = (1 until offset).count { (d.length - it) % 3 == 0 }
        val mapping = object : androidx.compose.ui.text.input.OffsetMapping {
            override fun originalToTransformed(offset: Int) = offset + spacesBefore(offset)
            override fun transformedToOriginal(offset: Int): Int {
                var k = 0
                while (k < d.length && originalToTransformed(k + 1) <= offset) k++
                return k
            }
        }
        return androidx.compose.ui.text.input.TransformedText(androidx.compose.ui.text.AnnotatedString(out.toString()), mapping)
    }
}

/** Несколько фото (до [limit]): миниатюры, убрать, нажатие делает фото главным. */
@Composable
fun MultiPhotoField(images: List<String>, limit: Int, onChange: (List<String>) -> Unit) {
    val context = LocalContext.current
    val p = LocalPalette.current
    val left = (limit - images.size).coerceAtLeast(1)
    val multi = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxOf(2, left))) { uris ->
        val added = uris.take(limit - images.size).mapNotNull { MediaStore.save(context, it) }
        onChange(images + added)
    }
    val single = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) MediaStore.save(context, uri)?.let { onChange(images + it) }
    }
    if (images.isNotEmpty()) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            images.forEachIndexed { index, id ->
                MediaStore.get(context, id)?.let { bitmap ->
                    Box(Modifier.size(88.dp).clip(RoundedCornerShape(10.dp)).clickable {
                        if (index > 0) onChange(listOf(id) + images.filterIndexed { i, _ -> i != index })
                    }) {
                        Image(bitmap.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        Text("✕", Modifier.align(Alignment.TopEnd).padding(4.dp).background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(50))
                            .clickable { onChange(images.filterIndexed { i, _ -> i != index }) }.padding(horizontal = 7.dp, vertical = 2.dp),
                            color = Color.White, fontSize = 13.sp)
                        if (index == 0) Text("Главное", Modifier.align(Alignment.BottomStart).padding(4.dp)
                            .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 1.dp),
                            color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton({
            val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
            if (limit - images.size > 1) multi.launch(request) else single.launch(request)
        }, enabled = images.size < limit) { Text("📷 Добавить фото") }
        Spacer(Modifier.weight(1f))
        Text("${images.size} / $limit", color = p.textSecondary, fontSize = 13.sp)
    }
    if (images.size > 1) Secondary("Нажмите на фото, чтобы сделать его главным. До $limit фото.", size = 12)
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
