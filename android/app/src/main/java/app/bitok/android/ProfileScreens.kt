@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Профиль как в Telegram: карточка, затем разделы «Редактировать профиль», «Места», «Групповые», «Трофеи»,
// «Настройки», «Помощь».
package app.bitok.android

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate

@Composable
fun ProfileScreen(app: AppState) {
    val b = app.backend
    Screen(if (app.isCoach) "Тренер" else "Игрок", app) {
        if (app.isCoach) CoachCard(app) else {
            PlayerCard(app)
            ProgressBlock(app)
            NextTraining(app)
            Season(app)
            ProfileGifts(app, app.me)
        }
        GlassCard(Modifier, null) {
            MenuRow(Icons.Filled.EditNote, "Редактировать профиль") { app.push(Route.EditProfile) }
            if (app.isCoach) {
                HorizontalDivider()
                MenuRow(Icons.Filled.Place, "Места и расписание") { app.push(Route.Venues) }
                HorizontalDivider()
                MenuRow(Icons.Filled.Groups, "Групповые тренировки") { app.push(Route.Groups) }
                HorizontalDivider()
                MenuRow(Icons.Filled.EditNote, "Упражнения и уроки") { app.push(Route.CoachExercises) }
            } else {
                HorizontalDivider()
                MenuRow(Icons.Filled.Groups, "Друзья · ${b.friends(app.me).size}" + if (b.incomingFriendRequests(app.me).isNotEmpty()) " · новые запросы" else "") { app.push(Route.Friends) }
                HorizontalDivider()
                MenuRow(Icons.Filled.EmojiEvents, "Трофеи и достижения") { app.push(Route.Trophies) }
            }
            HorizontalDivider()
            MenuRow(Icons.Filled.Settings, "Настройки") { app.push(Route.Settings) }
            HorizontalDivider()
            MenuRow(Icons.AutoMirrored.Filled.HelpOutline, "Помощь") { app.push(Route.Help) }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun MenuRow(icon: ImageVector, title: String, onClick: () -> Unit) {
    val p = LocalPalette.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(30.dp).background(p.accent, RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = p.onAccent, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(title, Modifier.weight(1f), color = p.text, fontSize = 16.sp)
        Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
    }
}

@Composable
private fun GradientCard(content: @Composable () -> Unit) {
    val p = LocalPalette.current
    Column(
        Modifier.fillMaxWidth().background(Brush.linearGradient(listOf(p.accent, p.accent.copy(alpha = 0.8f), p.accent2)), RoundedCornerShape(24.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) { content() }
}

@Composable
private fun PlayerCard(app: AppState) {
    val b = app.backend
    val progress = b.progress(app.me)
    val rating = b.rating(app.me)
    GradientCard {
        Row {
            Column(Modifier.weight(1f)) {
                Text("${rating ?: 0}", fontSize = 48.sp, fontWeight = FontWeight.Black, color = Color.White)
                Text(b.level(rating).uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.85f))
                Spacer(Modifier.height(8.dp))
                Text(b.name(app.me), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text("👑 Чемпион клуба", fontSize = 13.sp, color = Color.White.copy(alpha = 0.9f))
            }
            Box(Modifier.size(92.dp).background(Brush.sweepGradient(listOf(Color(0xFFFFF6C8), Color(0xFFF2C94C), Color(0xFFB8860B), Color(0xFFFFF6C8))), RoundedCornerShape(46.dp)),
                contentAlignment = Alignment.Center) {
                Box(Modifier.clickable { if (AvatarStore.get(app.context, app.me) != null) app.push(Route.PhotoViewer(app.me)) }) { Avatar(b.person(app.me), 84.dp) }
            }
        }
        Row {
            Metric.entries.forEach { m ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${progress[m] ?: 0}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    Text(m.short, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.8f))
                }
            }
        }
    }
}

@Composable
private fun NextTraining(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    val next = b.bookingsOfStudent(app.me).filter { it.status.holdsSlot && it.start > System.currentTimeMillis() }.minByOrNull { it.start }
    GlassCard(onClick = { app.tab = Tab.CALENDAR }) {
        Secondary("Следующая тренировка")
        if (next != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Title("${Fmt.shortDay(next.start)} · ${Fmt.time(next.start)}")
                    Secondary("${b.name(next.coachId)} · ${b.place(next.slotId)}")
                }
                Text(Fmt.time(next.start), fontSize = 24.sp, fontWeight = FontWeight.Bold, color = p.accent)
            }
        } else {
            Title("Пока не записаны")
            Secondary("Нажмите, чтобы выбрать время")
        }
    }
}

@Composable
private fun Season(app: AppState) {
    val p = LocalPalette.current
    val start = LocalDate.of(LocalDate.now().year, 9, 1).at(0)
    val done = app.backend.bookingsOfStudent(app.me).count { it.status == BookingStatus.COMPLETED && it.start >= start }.coerceAtMost(10)
    GlassCard {
        Row { Title("Сезон «Осень»"); Secondary(" · $done / 10 тренировок", size = 15) }
        Box(Modifier.fillMaxWidth().height(8.dp).background(p.textSecondary.copy(alpha = 0.15f), RoundedCornerShape(4.dp))) {
            Box(Modifier.fillMaxWidth(done / 10f).height(8.dp).background(p.accent, RoundedCornerShape(4.dp)))
        }
        Secondary(if (done >= 10) "Награда получена: тема «Графит» 🎉" else "Награда: тема профиля «Графит»")
    }
}

@Composable
private fun CoachCard(app: AppState) {
    val b = app.backend
    val info = b.coachInfo(app.me)
    val week = (0L..6L).map { LocalDate.now().plusDays(it) }.flatMap { b.bookingsOf(app.me, it) }.count { it.status.holdsSlot }
    val waiting = b.state.bookings.count { it.coachId == app.me && it.status == BookingStatus.COMPLETED && !b.isEvaluated(it.id) }
    GradientCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.clickable { if (AvatarStore.get(app.context, app.me) != null) app.push(Route.PhotoViewer(app.me)) }) { Avatar(b.person(app.me), 72.dp) }
            Spacer(Modifier.width(12.dp))
            Column {
                Text(b.name(app.me), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text(info.rank, color = Color.White.copy(alpha = 0.85f))
                Text(b.venues(app.me).joinToString(" · ") { it.name }, fontSize = 13.sp, color = Color.White.copy(alpha = 0.85f))
            }
        }
        Text("🕒 ${info.hours}", fontSize = 13.sp, color = Color.White)
        if (info.about.isNotBlank()) Text(info.about, fontSize = 13.sp, color = Color.White.copy(alpha = 0.9f))
        Row {
            listOf("${b.studentsOf(app.me).size}" to "учеников", "$week" to "за 7 дней", "${b.pendingRequests(app.me).size}" to "заявок", "$waiting" to "оценить")
                .forEach { (v, t) ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(v, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
                        Text(t, fontSize = 11.sp, color = Color.White.copy(alpha = 0.85f))
                    }
                }
        }
    }
}

@Composable
fun EditProfileScreen(app: AppState) {
    val b = app.backend
    val context = LocalContext.current
    val initial = b.profile(app.me)
    val info = if (app.isCoach) b.coachInfo(app.me) else null
    var first by remember { mutableStateOf(initial.firstName) }
    var last by remember { mutableStateOf(initial.lastName) }
    var city by remember { mutableStateOf(initial.city) }
    var discipline by remember { mutableStateOf(initial.discipline) }
    var about by remember { mutableStateOf(initial.about) }
    var birth by remember { mutableStateOf(initial.birthDate?.toDate()) }
    var visibility by remember { mutableStateOf(initial.birthdayVisibility) }
    var rank by remember { mutableStateOf(info?.rank ?: "") }
    var hours by remember { mutableStateOf(info?.hours ?: "") }
    var coachAbout by remember { mutableStateOf(info?.about ?: "") }
    var price by remember { mutableStateOf(info?.price?.toString() ?: "") }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        // Сначала редактор: сдвиг и масштаб с предпросмотром.
        if (uri != null) app.push(Route.CropAvatar(uri.toString()))
    }
    Screen("Профиль", app, bottom = {
        PrimaryButton("Сохранить", Modifier.padding(16.dp), enabled = first.isNotBlank()) {
            b.updateProfile(app.me, Profile(first.trim(), last.trim(), city.trim(), discipline, about.trim(), birth?.at(12), visibility))
            if (app.isCoach) {
                b.updateCoachInfo(app.me, CoachInfo(rank.trim(), hours.trim(), coachAbout.trim(), price.toIntOrNull() ?: b.coachInfo(app.me).price))
            }
            app.pop()
        }
    }) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            // Нажатие на фото открывает просмотр; удаление — отдельной кнопкой.
            Box(Modifier.clickable { if (AvatarStore.get(context, app.me) != null) app.push(Route.PhotoViewer(app.me)) }) { Avatar(b.person(app.me), 96.dp) }
            TextButton({ picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Text(if (AvatarStore.get(context, app.me) == null) "📷 Загрузить фото" else "📷 Изменить фото")
            }
            if (AvatarStore.get(context, app.me) != null) {
                TextButton({ AvatarStore.set(context, app.me, null) }) { Text("Удалить фото", color = LocalPalette.current.cancelled) }
            }
        }
        OutlinedTextField(first, { first = it }, Modifier.fillMaxWidth(), label = { Text("Имя") }, singleLine = true)
        OutlinedTextField(last, { last = it }, Modifier.fillMaxWidth(), label = { Text("Фамилия") }, singleLine = true)
        OutlinedTextField(city, { city = it }, Modifier.fillMaxWidth(), label = { Text("Город") }, singleLine = true)
        Title("Дисциплина")
        listOf("Русский бильярд", "Пул", "Снукер", "Карамболь").chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { d -> Chip(d, d == discipline, Modifier.weight(1f)) { discipline = d } } }
        }
        if (app.isCoach) {
            Title("Тренер")
            OutlinedTextField(rank, { rank = it }, Modifier.fillMaxWidth(), label = { Text("Квалификация: мастер спорта, КМС…") }, singleLine = true)
            OutlinedTextField(hours, { hours = it }, Modifier.fillMaxWidth(), label = { Text("Часы работы, например Пн–Сб 16:00–22:00") })
            OutlinedTextField(coachAbout, { coachAbout = it }, Modifier.fillMaxWidth(), label = { Text("Коротко о себе: опыт, специализация") }, minLines = 2)
            OutlinedTextField(price, { price = it.filter { c -> c.isDigit() } }, Modifier.fillMaxWidth(), label = { Text("Базовая цена") },
                suffix = { Text("₽") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
            Secondary("Цену видит только ученик в своей записи. Для отдельного ученика её можно изменить в его карточке (вкладка «Ученики»).")
        } else {
            OutlinedTextField(about, { about = it }, Modifier.fillMaxWidth(), label = { Text("Чего хотите добиться") }, minLines = 2)
        }
        Title("День рождения")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Указать дату рождения", Modifier.weight(1f), color = LocalPalette.current.text)
            Switch(birth != null, { birth = if (it) (birth ?: LocalDate.now().minusYears(18)) else null })
        }
        birth?.let { date ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SecondaryButton("−") { birth = date.minusDays(1) }
                Text(date.format(java.time.format.DateTimeFormatter.ofPattern("d MMMM yyyy", java.util.Locale("ru", "RU"))), Modifier.weight(1f),
                    color = LocalPalette.current.text, fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                SecondaryButton("+") { if (date < LocalDate.now()) birth = date.plusDays(1) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SecondaryButton("−1 мес.", Modifier.weight(1f)) { birth = date.minusMonths(1) }
                SecondaryButton("−1 год", Modifier.weight(1f)) { birth = date.minusYears(1) }
                SecondaryButton("+1 год", Modifier.weight(1f)) { if (date.plusYears(1) < LocalDate.now()) birth = date.plusYears(1) }
            }
            if (!app.isCoach) {
                Secondary("Видят другие ученики:")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BirthdayVisibility.entries.forEach { v -> Chip(v.title, v.key == visibility, Modifier.weight(1f)) { visibility = v.key } }
                }
            }
        }
        Secondary(if (app.isCoach) "Ученики не видят вашу дату рождения." else "По умолчанию другие ученики её не видят. Тренер видит дату всегда, чтобы поздравить. Ученикам младше 14 лет «Биток Про» за полцены.")
        Secondary("Телефон: ${app.account?.phone}")
    }
}

@Composable
fun SettingsScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    var confirmReset by remember { mutableStateOf(false) }
    Screen("Настройки", app) {
        Title("Оформление")
        Appearance.entries.forEach { a -> Chip(a.title, a == app.appearance, Modifier.fillMaxWidth()) { app.changeAppearance(a) } }
        Title("Размер текста")
        TextSize.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { t -> Chip(t.title, t == app.textSize, Modifier.weight(1f)) { app.changeTextSize(t) } } }
        }
        Secondary("Меняет размер текста во всём приложении, независимо от настроек телефона.")
        GlassCard(onClick = { app.push(Route.AppIcon) }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val current = AppIcons.firstOrNull { it.key == AppIconSwitcher.current(app.context) } ?: AppIcons.first()
                androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(current.preview), null,
                    Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)))
                Spacer(Modifier.width(12.dp))
                Title("Значок приложения", Modifier.weight(1f))
                Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
            }
        }
        GlassCard {
            Title("Уведомления")
            var on by remember { mutableStateOf(app.notifier.enabled) }
            ToggleRow("Уведомления о заявках и сообщениях", on) { on = it; app.notifier.enabled = it }
            Secondary("Напомнить о тренировке")
            var minutes by remember { mutableStateOf(app.notifier.reminderMinutes) }
            listOf(5, 15, 30, 60, 120, 1440).chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { m -> Chip("за ${Notifier.humanize(m)}", m == minutes, Modifier.weight(1f)) { minutes = m; app.notifier.reminderMinutes = m } }
                }
            }
            Secondary("Для проверки: у Алексея есть «Тест-зал 24/7» — слот каждый час, записаться можно за 5 минут до начала. Подтвердите заявку тренером — придёт уведомление и напоминание.")
        }
        if (app.isCoach) {
            GlassCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Title("Сетка недели в календаре")
                        Secondary("Цветная сетка «дни × часы». Выключите, чтобы видеть неделю списком.")
                    }
                    Switch(app.weekGrid, { app.changeWeekGrid(it) })
                }
            }
        } else {
            val privacy = b.state.privacy
            GlassCard {
                Title("Приватность")
                ToggleRow("Показывать прогресс другим ученикам", privacy.showProgress) { b.setPrivacy(privacy.copy(showProgress = it)) }
                ToggleRow("Показывать достижения другим ученикам", privacy.showAchievements) { b.setPrivacy(privacy.copy(showAchievements = it)) }
                ToggleRow("Показывать меня в «Учениках»", privacy.discoverable) { b.setPrivacy(privacy.copy(discoverable = it)) }
                Secondary("Дата рождения для других учеников:")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BirthdayVisibility.entries.forEach { v ->
                        Chip(v.title, v.key == b.profile(app.me).birthdayVisibility, Modifier.weight(1f)) { b.updateProfile(app.me, b.profile(app.me).copy(birthdayVisibility = v.key)) }
                    }
                }
                Secondary("Ваш тренер видит прогресс всегда. Телефон другим ученикам не показывается без обмена номерами.")
            }
        }
        GlassCard {
            Title("Демо")
            Secondary("Данные общие для всех тестовых учёток на этом телефоне.")
            SecondaryButton("Сбросить демо-данные", Modifier.fillMaxWidth(), p.cancelled) { confirmReset = true }
        }
        GlassCard {
            Title("Аккаунт")
            Text("${app.account?.roleTitle}: ${b.name(app.me)}", color = p.text)
            Text("Телефон: ${app.account?.phone}", color = p.text)
            SecondaryButton("Выйти", Modifier.fillMaxWidth(), p.cancelled) { app.signOut() }
        }
    }
    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("Сбросить демо-данные?") },
            text = { Text("Удалятся все записи, сообщения и оценки, вернутся начальные данные.") },
            confirmButton = { TextButton({ confirmReset = false; b.reset() }) { Text("Сбросить", color = p.cancelled) } },
            dismissButton = { TextButton({ confirmReset = false }) { Text("Отмена") } },
        )
    }
}

@Composable
private fun ToggleRow(title: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), color = LocalPalette.current.text, fontSize = 15.sp)
        Switch(value, onChange)
    }
}

@Composable
fun HelpScreen(app: AppState) {
    val p = LocalPalette.current
    val topics = if (app.isCoach) coachHelp else studentHelp
    var opened by remember { mutableStateOf<String?>(topics.first().first) }
    Screen("Помощь", app) {
        Secondary(if (app.isCoach) "Коротко о том, где что находится в приложении тренера." else "Коротко о том, где что находится и что можно делать.", size = 15)
        if (!app.isCoach && app.backend.hasSubscription(app.me)) {
            GlassCard {
                Title("Биток Про: камера-помощник")
                ProGuide()
            }
        }
        Title("Экраны с подсказками")
        (if (app.isCoach) coachShots else studentShots).forEach { shot ->
            GlassCard {
                Text(shot.title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
                androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(shot.image), shot.title,
                    Modifier.fillMaxWidth().height(460.dp).clip(RoundedCornerShape(18.dp)),
                    contentScale = androidx.compose.ui.layout.ContentScale.Fit)
                shot.items.forEachIndexed { i, text ->
                    Row(verticalAlignment = Alignment.Top) {
                        Box(Modifier.size(22.dp).background(p.accent, RoundedCornerShape(11.dp)), contentAlignment = Alignment.Center) {
                            Text("${i + 1}", color = p.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.width(8.dp))
                        Text(text, color = p.text, fontSize = 15.sp)
                    }
                }
            }
        }
        Title("Пошагово")
        topics.forEach { (title, steps) ->
            GlassCard(onClick = { opened = if (opened == title) null else title }) {
                Row { Title(title, Modifier.weight(1f)); Text(if (opened == title) "−" else "+", fontSize = 22.sp, color = p.accent) }
                if (opened == title) {
                    steps.forEachIndexed { i, step ->
                        Row(verticalAlignment = Alignment.Top) {
                            Box(Modifier.size(22.dp).background(p.accent, RoundedCornerShape(11.dp)), contentAlignment = Alignment.Center) {
                                Text("${i + 1}", color = p.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            }
                            Spacer(Modifier.width(8.dp))
                            Text(step, color = p.text, fontSize = 15.sp)
                        }
                    }
                }
            }
        }
        GlassCard {
            Title("Вкладки")
            listOf(
                "Календарь" to if (app.isCoach) "расписание и заявки" else "запись к тренеру",
                (if (app.isCoach) "Ученики" else "Прогресс") to if (app.isCoach) "список, оценки, цены" else "навыки и достижения",
                "Чат" to "переписка, игроки, уведомления",
                "Контент" to "новости, турниры, магазин",
                "Профиль" to "карточка, настройки, помощь",
            ).forEach { (t, d) -> Row { Text(t, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, color = p.text); Secondary(d) } }
        }
    }
}

private val studentHelp = listOf(
    "Как записаться на тренировку" to listOf(
        "Откройте вкладку «Календарь» и выберите тренера вверху.",
        "Дни со свободным временем выделены. Нажмите на день, затем на время.",
        "Нажмите «Продолжить», проверьте запись и нажмите «Записаться».",
        "Откроется чат с тренером: там видно, подтвердил ли он заявку.",
    ),
    "Групповые (игровые) тренировки" to listOf(
        "В «Календаре» под расписанием есть блок «Групповые тренировки».",
        "Нажмите на тренировку — увидите место, цену и сколько осталось мест.",
        "«Записаться» — и вы в списке участников. Передумали — «Не смогу прийти».",
    ),
    "Отменить или перенести" to listOf(
        "Нажмите на запись в «Моих записях» или на карточку в чате.",
        "«Отменить запись». Меньше чем за 12 часов отмена считается поздней.",
        "«Перенести на другое время» — запись отменится, откроется календарь тренера.",
    ),
    "Тренер предложил время" to listOf(
        "В чате появится карточка «Предложение тренировки».",
        "«Принять» — запись сразу подтверждена. «Другое время» — откроется календарь. «Нет» — отказ.",
    ),
    "Прогресс и достижения" to listOf(
        "После тренировки тренер оценивает 5 навыков от 0 до 100.",
        "Во вкладке «Прогресс» — радар навыков, график и комментарий тренера.",
        "Медали — в «Профиле» → «Трофеи и достижения».",
    ),
    "Игроки клуба и обмен номерами" to listOf(
        "«Чат» → «Игроки» — другие ученики клуба. Нажмите на игрока, затем «Написать».",
        "Кнопка «⊕» в чате: «Предложить сыграть» или «Обменяться номерами».",
        "Номера видны только после согласия обоих.",
    ),
    "Контент: новости и магазин" to listOf(
        "«Новости» — турниры и события клуба от тренеров.",
        "«Магазин» — кии, мелки, перчатки и услуги ремонта по категориям. «Написать продавцу» открывает чат.",
    ),
    "Профиль и настройки" to listOf(
        "«Редактировать профиль» — имя, город, дисциплина и фото.",
        "«Настройки» — тема, размер текста, приватность, выход.",
    ),
)

private val coachHelp = listOf(
    "Где и когда я тренирую" to listOf(
        "«Профиль» → «Места и расписание». Добавьте место (например, «Флагман» или «Тиджон»).",
        "Отметьте дни и часы начала тренировок — из них получатся свободные слоты на 3 недели вперёд.",
        "«Кто может записаться»: все ученики или только выбранные. Остальные это место не увидят.",
    ),
    "Календарь и заявки" to listOf(
        "Вкладка «Календарь»: «День», «Неделя» (сетка или список) и «Месяц».",
        "Новые заявки — сверху: «Подтвердить», «Отклонить» или «Предложить другое время».",
        "Нажмите на любую карточку, чтобы открыть подробности.",
    ),
    "Предложить ученику время" to listOf(
        "В чате с учеником нажмите 📅 и выберите день и время.",
        "Ученик примет предложение одной кнопкой — запись сразу будет подтверждена.",
    ),
    "Поменять учеников местами" to listOf(
        "Откройте подтверждённую тренировку (в календаре или в чате) → «Поменять местами».",
        "Выберите другого ученика — они поменяются временем, оба получат сообщение.",
    ),
    "Групповые тренировки" to listOf(
        "«Профиль» → «Групповые тренировки» → «Создать групповую».",
        "Укажите место, день, время, число мест и цену. Ученики запишутся сами.",
    ),
    "Цены" to listOf(
        "Базовая цена — в «Редактировать профиль».",
        "Своя цена для ученика — «Ученики» → ученик → «Цена для ученика».",
    ),
    "Оценка после тренировки" to listOf(
        "Откройте прошедшую запись → «Оценить ученика».",
        "5 навыков от 0 до 100 и комментарий — ученик сразу увидит прогресс.",
    ),
    "Публикации" to listOf(
        "«Контент» → «Новости» → «⊕»: новость или анонс турнира.",
        "«Контент» → «Магазин» → «⊕»: товар или услуга ремонта и обслуживания кия.",
    ),
)

/** Редактор аватарки: перетащите и приблизите фото; снизу — как оно будет выглядеть в кружках разного размера. */
@Composable
fun CropAvatarScreen(app: AppState, uri: String) {
    val p = LocalPalette.current
    val context = LocalContext.current
    val bitmap = remember(uri) { loadBitmap(context, android.net.Uri.parse(uri)) }
    if (bitmap == null) return Screen("Фото профиля", app) { Secondary("Не удалось открыть фото") }
    val image = remember(bitmap) { bitmap.asImageBitmap() }
    var zoom by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    val sideDp = 300.dp
    val side = with(androidx.compose.ui.platform.LocalDensity.current) { sideDp.toPx() }
    fun clamp(o: androidx.compose.ui.geometry.Offset, z: Float): androidx.compose.ui.geometry.Offset {
        val fill = maxOf(side / bitmap.width, side / bitmap.height) * z
        val limitX = maxOf(0f, (bitmap.width * fill - side) / 2)
        val limitY = maxOf(0f, (bitmap.height * fill - side) / 2)
        return androidx.compose.ui.geometry.Offset(o.x.coerceIn(-limitX, limitX), o.y.coerceIn(-limitY, limitY))
    }

    @Composable
    fun Cropped(size: androidx.compose.ui.unit.Dp) {
        androidx.compose.foundation.Canvas(Modifier.size(size).clip(androidx.compose.foundation.shape.CircleShape)) {
            val factor = this.size.width / side
            val fill = maxOf(side / bitmap.width, side / bitmap.height) * zoom * factor
            drawContext.canvas.save()
            drawContext.transform.translate(this.size.width / 2 + offset.x * factor, this.size.height / 2 + offset.y * factor)
            drawContext.transform.scale(fill, fill, androidx.compose.ui.geometry.Offset.Zero)
            drawImage(image, topLeft = androidx.compose.ui.geometry.Offset(-bitmap.width / 2f, -bitmap.height / 2f))
            drawContext.canvas.restore()
        }
    }

    Screen("Фото профиля", app, bottom = {
        PrimaryButton("Готово", Modifier.padding(16.dp)) {
            val result = cropAvatar(bitmap, side, zoom, offset.x, offset.y)
            val file = java.io.File(context.cacheDir, "avatar.jpg")
            file.outputStream().use { result.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it) }
            AvatarStore.set(context, app.me, android.net.Uri.fromFile(file))
            app.pop()
        }
    }) {
        Box(
            Modifier.fillMaxWidth().height(sideDp),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(sideDp).clip(RoundedCornerShape(4.dp))
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, gestureZoom, _ ->
                            zoom = (zoom * gestureZoom).coerceIn(1f, 5f)
                            offset = clamp(offset + pan, zoom)
                        }
                    },
            ) {
                androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                    val fill = maxOf(side / bitmap.width, side / bitmap.height) * zoom
                    drawContext.canvas.save()
                    drawContext.transform.translate(this.size.width / 2 + offset.x, this.size.height / 2 + offset.y)
                    drawContext.transform.scale(fill, fill, androidx.compose.ui.geometry.Offset.Zero)
                    drawImage(image, topLeft = androidx.compose.ui.geometry.Offset(-bitmap.width / 2f, -bitmap.height / 2f))
                    drawContext.canvas.restore()
                    // Затемнение вне круга
                    val hole = androidx.compose.ui.graphics.Path().apply { addOval(androidx.compose.ui.geometry.Rect(0f, 0f, size.width, size.height)) }
                    val frame = androidx.compose.ui.graphics.Path().apply { addRect(androidx.compose.ui.geometry.Rect(0f, 0f, size.width, size.height)) }
                    val outside = androidx.compose.ui.graphics.Path.combine(androidx.compose.ui.graphics.PathOperation.Difference, frame, hole)
                    drawPath(outside, Color.Black.copy(alpha = 0.55f))
                    drawCircle(Color.White, radius = size.width / 2, style = androidx.compose.ui.graphics.drawscope.Stroke(4f))
                }
            }
        }
        Secondary("Перетащите фото и разведите пальцы, чтобы приблизить", Modifier.align(Alignment.CenterHorizontally), 14)
        androidx.compose.material3.Slider(value = zoom, onValueChange = { zoom = it; offset = clamp(offset, it) }, valueRange = 1f..5f)
        Secondary("Так будет видно в приложении", Modifier.align(Alignment.CenterHorizontally))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.Bottom) {
            listOf(96.dp to "Профиль", 56.dp to "Карточка", 40.dp to "Список", 28.dp to "Чат").forEach { (size, title) ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Cropped(size)
                    Secondary(title, size = 11)
                }
            }
        }
    }
}

@Composable
fun AppIconScreen(app: AppState) {
    val p = LocalPalette.current
    var current by remember { mutableStateOf(AppIconSwitcher.current(app.context)) }
    Screen("Значок приложения", app) {
        Secondary("Выберите значок для рабочего стола. Лаунчер может обновить его через несколько секунд.", size = 14)
        AppIcons.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { option ->
                    GlassCard(Modifier.weight(1f), onClick = { AppIconSwitcher.apply(app.context, option.key); current = option.key }) {
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(option.preview), option.title,
                                Modifier.size(84.dp).clip(RoundedCornerShape(20.dp))
                                    .then(if (option.key == current) Modifier.border(3.dp, p.accent, RoundedCornerShape(20.dp)) else Modifier))
                            Text(option.title, fontWeight = FontWeight.SemiBold, color = p.text, fontSize = 14.sp)
                            Secondary(option.subtitle, size = 12)
                            if (option.key == current) Text("✓ Выбран", color = p.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** «Прогресс» в профиле ученика — отдельный выделенный блок. */
@Composable
private fun ProgressBlock(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    val progress = b.progress(app.me)
    val rating = b.rating(app.me)
    Column(
        Modifier.fillMaxWidth().background(p.accent.copy(alpha = 0.08f), RoundedCornerShape(22.dp))
            .border(2.dp, p.accent.copy(alpha = 0.45f), RoundedCornerShape(22.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("📈 Прогресс", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.text, modifier = Modifier.weight(1f))
            Text(rating?.toString() ?: "—", fontSize = 28.sp, fontWeight = FontWeight.Black, color = p.accent)
        }
        Secondary("Уровень: ${b.level(rating)} · оценки тренера по упражнениям")
        Metric.entries.forEach { MetricBar(it.title, progress[it] ?: 0) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PrimaryButton("Подробнее", Modifier.weight(1f)) { app.push(Route.Progress) }
            SecondaryButton("📋 Упражнения", Modifier.weight(1f)) { app.push(Route.Exercises(app.me)) }
        }
    }
}
