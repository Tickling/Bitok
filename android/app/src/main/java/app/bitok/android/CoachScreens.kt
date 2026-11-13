@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Экраны тренера: расписание (день / неделя-сетка / месяц), ученики, места, групповые тренировки.
package app.bitok.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

@Composable
fun <T> Segmented(options: List<T>, selected: T, title: (T) -> String, onSelect: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            SegmentedButton(selected = option == selected, onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size)) { Text(title(option), maxLines = 1) }
        }
    }
}

private enum class Mode(val title: String) { DAY("День"), WEEK("Неделя"), MONTH("Месяц") }

@Composable
fun CoachScheduleScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    val me = app.me
    var mode by remember { mutableStateOf(if (app.uiPage == "week") Mode.WEEK else Mode.DAY) }
    var day by remember { mutableStateOf(if (app.uiPage == "tomorrow") LocalDate.now().plusDays(1) else LocalDate.now()) }

    Screen("Расписание", app) {
        Segmented(Mode.entries, mode, { it.title }) { mode = it }
        val requests = b.pendingRequests(me)
        if (requests.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.HourglassTop, null, tint = p.pending)
                Text("Новые заявки · ${requests.size}", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.pending)
            }
            requests.forEach { booking ->
                // Нажатие на любое место карточки открывает заявку; кнопки — отдельные действия.
                GlassCard(onClick = { app.push(Route.BookingDetail(booking.id)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(b.person(booking.studentId), 36.dp)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(b.name(booking.studentId), fontWeight = FontWeight.SemiBold, color = p.text)
                            Secondary("${Fmt.shortDay(booking.start)} · ${Fmt.time(booking.start)} · ${b.venue(b.slot(booking.slotId)?.venueId ?: "")?.name ?: ""}")
                        }
                        Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SecondaryButton("Отклонить", color = p.cancelled) { app.run { b.reject(booking.id) } }
                        PrimaryButton("Подтвердить", Modifier.weight(1f)) { app.run { b.approve(booking.id) } }
                    }
                    SecondaryButton("Предложить другое время", Modifier.fillMaxWidth(), icon = Icons.Filled.Event) {
                        app.push(Route.Propose(booking.studentId, booking.id))
                    }
                }
            }
        }
        when (mode) {
            Mode.DAY -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton({ day = day.minusDays(1) }) { Icon(Icons.Filled.ChevronLeft, "Предыдущий день", tint = p.accent) }
                    Text((if (day == LocalDate.now()) "Сегодня, " else "") + Fmt.dayTitle(day), Modifier.weight(1f),
                        textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, color = p.text)
                    IconButton({ day = day.plusDays(1) }) { Icon(Icons.Filled.ChevronRight, "Следующий день", tint = p.accent) }
                }
                DayEntries(app, day)
            }
            Mode.WEEK -> if (app.weekGrid) WeekGrid(app, day, { day = it }) { day = it; mode = Mode.DAY } else WeekList(app, day) { day = it }
            Mode.MONTH -> {
                val month = day.withDayOfMonth(1)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton({ day = month.minusMonths(1) }) { Icon(Icons.Filled.ChevronLeft, null, tint = p.accent) }
                    Text(Fmt.monthYear(month), Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, color = p.text)
                    IconButton({ day = month.plusMonths(1) }) { Icon(Icons.Filled.ChevronRight, null, tint = p.accent) }
                }
                val working = b.state.slots.filter { it.coachId == me }.map { it.start.toDate() }.toSet() +
                    b.groupsOf(me).map { it.start.toDate() }
                val marked = b.state.bookings.filter { it.coachId == me && it.status.holdsSlot }.map { it.start.toDate() }.toSet() +
                    b.groupsOf(me).map { it.start.toDate() }
                MonthGrid(month, day, working, marked) { day = it }
                Title(Fmt.dayTitle(day))
                DayEntries(app, day)
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun DayEntries(app: AppState, day: LocalDate) {
    val p = LocalPalette.current
    val b = app.backend
    val me = app.me
    val bookings = b.bookingsOf(me, day)
    val free = b.coachFreeSlots(me, day)
    val groups = b.groupsOn(me, day)
    if (bookings.isEmpty() && free.isEmpty() && groups.isEmpty()) Secondary("Выходной — слотов нет")
    val entries: List<Pair<Long, @Composable () -> Unit>> =
        bookings.map { booking -> booking.start to @Composable { CoachBookingRow(app, booking) } } +
            groups.map { g -> g.start to @Composable { GroupCard(app, g) } } +
            free.map { slot ->
                slot.start to @Composable {
                    Text(
                        "+  ${Fmt.time(slot.start)} · свободно · ${b.venue(slot.venueId)?.name ?: ""}",
                        Modifier.fillMaxWidth().border(1.dp, p.textSecondary.copy(alpha = 0.4f), RoundedCornerShape(18.dp)).padding(14.dp),
                        color = p.textSecondary,
                    )
                }
            }
    entries.sortedBy { it.first }.forEach { it.second() }
}

@Composable
private fun CoachBookingRow(app: AppState, booking: Booking) {
    val p = LocalPalette.current
    val b = app.backend
    val student = b.person(booking.studentId)
    GlassCard(onClick = { app.push(Route.BookingDetail(booking.id)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(4.dp).height(72.dp).background(statusColor(booking.status), RoundedCornerShape(2.dp)))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("${Fmt.time(booking.start)} · ${student?.name}", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
                StatusPill(booking.status)
                Secondary(b.place(booking.slotId))
                if (b.isGroupBooking(booking.id)) Text("👥 Хочет в группу", color = p.accent2, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                Text("📞 ${student?.phone}", color = p.accent, fontSize = 14.sp)
                if (booking.status == BookingStatus.COMPLETED && !b.isEvaluated(booking.id)) {
                    Text("✍️ Нужно оценить", color = p.pending, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                }
            }
            Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
        }
    }
}

private fun weekStart(day: LocalDate) = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

@Composable
private fun WeekList(app: AppState, day: LocalDate, onDay: (LocalDate) -> Unit) {
    val p = LocalPalette.current
    val start = weekStart(day)
    val days = (0L..6L).map { start.plusDays(it) }
    WeekHeader(days, { onDay(day.minusWeeks(1)) }) { onDay(day.plusWeeks(1)) }
    days.forEach { d ->
        val bookings = app.backend.bookingsOf(app.me, d)
        Row {
            Text(Fmt.dayTitle(d), Modifier.weight(1f), fontWeight = FontWeight.SemiBold, color = p.text)
            val free = app.backend.coachFreeSlots(app.me, d).size
            if (free > 0) Secondary("свободно: $free")
        }
        if (bookings.isEmpty() && app.backend.groupsOn(app.me, d).isEmpty()) Secondary("Записей нет")
        bookings.forEach { CoachBookingRow(app, it) }
        app.backend.groupsOn(app.me, d).forEach { GroupCard(app, it) }
    }
}

@Composable
private fun WeekHeader(days: List<LocalDate>, onPrev: () -> Unit, onNext: () -> Unit) {
    val p = LocalPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onPrev) { Icon(Icons.Filled.ChevronLeft, "Предыдущая неделя", tint = p.accent) }
        Text("${days.first().dayOfMonth} – ${Fmt.dayTitle(days.last()).substringAfter(", ")}", Modifier.weight(1f),
            textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, color = p.text)
        IconButton(onNext) { Icon(Icons.Filled.ChevronRight, "Следующая неделя", tint = p.accent) }
    }
}

/** Сетка недели «дни × часы»: цвет клетки — статус. Включается в настройках. */
@Composable
private fun WeekGrid(app: AppState, day: LocalDate, onWeek: (LocalDate) -> Unit, onOpenDay: (LocalDate) -> Unit) {
    val p = LocalPalette.current
    val b = app.backend
    val me = app.me
    val start = weekStart(day)
    val days = (0L..6L).map { start.plusDays(it) }
    val hourSet = (b.venues(me).flatMap { it.hours } + b.state.bookings.filter { it.coachId == me }.map { it.start.hour() } +
        b.groupsOf(me, true).map { it.start.hour() }).toSet()
    val hours = if (hourSet.isEmpty()) (10..21).toList() else (hourSet.min()..hourSet.max()).toList()
    WeekHeader(days, { onWeek(day.minusWeeks(1)) }) { onWeek(day.plusWeeks(1)) }
    GlassCard {
        Row {
            Spacer(Modifier.width(28.dp))
            days.forEach { d ->
                Column(Modifier.weight(1f).clickable { onOpenDay(d) }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(Venue.WEEKDAYS[d.dayOfWeek.value - 1], fontSize = 11.sp, color = if (d == LocalDate.now()) p.accent else p.textSecondary)
                    Text("${d.dayOfMonth}", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (d == LocalDate.now()) p.accent else p.text)
                }
            }
        }
        hours.forEach { hour ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("%02d".format(hour), Modifier.width(28.dp), fontSize = 11.sp, color = p.textSecondary)
                days.forEach { d ->
                    val cellStart = d.at(hour)
                    val cellEnd = cellStart + 3_600_000
                    val group = b.groupsOn(me, d).firstOrNull { it.start < cellEnd && cellStart < it.end }
                    val booking = b.bookingsOf(me, d).firstOrNull { it.start < cellEnd && cellStart < it.end && (it.status.holdsSlot || it.status == BookingStatus.COMPLETED) }
                    val free = b.coachFreeSlots(me, d).any { it.start == cellStart }
                    val color = when {
                        group != null -> p.accent2
                        booking != null -> statusColor(booking.status)
                        free -> p.accent.copy(alpha = 0.18f)
                        else -> p.textSecondary.copy(alpha = 0.06f)
                    }
                    Box(
                        Modifier.weight(1f).height(26.dp).padding(1.5.dp).background(color, RoundedCornerShape(4.dp))
                            .clickable {
                                when {
                                    group != null -> app.push(Route.GroupDetail(group.id))
                                    booking != null -> app.push(Route.BookingDetail(booking.id))
                                    else -> onOpenDay(d)
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        when {
                            group != null -> Text("👥", fontSize = 10.sp)
                            booking != null -> Text(b.person(booking.studentId)?.initials ?: "", fontSize = 9.sp, color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        listOf(p.confirmed to "подтв.", p.pending to "заявка", p.completed to "прошла", p.accent2 to "группа", p.accent.copy(alpha = 0.18f) to "свободно")
            .forEach { (c, t) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).background(c, RoundedCornerShape(2.dp)))
                    Spacer(Modifier.width(3.dp))
                    Secondary(t, size = 12)
                }
            }
    }
    val week = days.flatMap { b.bookingsOf(me, it) }
    val trainings = week.count { it.status == BookingStatus.CONFIRMED || it.status == BookingStatus.COMPLETED } + days.sumOf { b.groupsOn(me, it).size }
    GlassCard {
        Text("📊 Неделя: $trainings тренировок · ${week.count { it.status == BookingStatus.AWAITING }} заявки · " +
            "${week.count { it.status == BookingStatus.COMPLETED && !b.isEvaluated(it.id) }} ждут оценки", fontWeight = FontWeight.SemiBold, color = p.text)
    }
    Secondary("Нажмите на клетку, чтобы открыть тренировку, или на день — чтобы посмотреть его списком.")
}

// region Ученики

@Composable
fun StudentsScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    var query by remember { mutableStateOf("") }
    Screen("Ученики", app) {
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Имя или телефон") }, singleLine = true)
        val digits = query.filter { it.isDigit() }
        val list = b.studentsOf(app.me).filter {
            query.isBlank() || it.name.contains(query, ignoreCase = true) || (digits.isNotEmpty() && it.phone.filter { c -> c.isDigit() }.contains(digits))
        }
        if (list.isEmpty()) Secondary("Учеников пока нет — они появятся после первой записи")
        list.forEach { student ->
            val waiting = b.bookingsOfStudent(student.id).any { it.coachId == app.me && it.status == BookingStatus.COMPLETED && !b.isEvaluated(it.id) }
            GlassCard(onClick = { app.push(Route.StudentDetail(student.id)) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(student, 44.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Title(student.name + if (b.isBirthdayToday(student.id)) " 🎂" else "")
                        Secondary(student.phone)
                        if (waiting) Text("✍️ Ждёт оценки", color = p.pending, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Text(b.rating(student.id)?.toString() ?: "—", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.accent)
                    Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
                }
            }
        }
    }
}

@Composable
fun StudentDetailScreen(app: AppState, studentId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val student = b.person(studentId)
    val progress = b.progress(studentId)
    var price by remember { mutableStateOf(b.price(app.me, studentId).toString()) }
    Screen(student?.name ?: "Ученик", app) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(student, 56.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Title(student?.name ?: "")
                Secondary(b.level(b.rating(studentId)))
                b.birthdayForCoach(studentId)?.let {
                    Text((if (b.isBirthdayToday(studentId)) "🎂 Сегодня день рождения! " else "🎂 ") + it, fontSize = 13.sp,
                        color = if (b.isBirthdayToday(studentId)) p.accent else p.textSecondary,
                        fontWeight = if (b.isBirthdayToday(studentId)) FontWeight.Bold else FontWeight.Normal)
                }
                Text("📞 ${student?.phone}", color = p.accent)
            }
            Text(b.rating(studentId)?.toString() ?: "—", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = p.accent)
        }
        GlassCard {
            Title("Навыки")
            Metric.entries.forEach { m -> MetricBar(m.title, progress[m] ?: 0) }
        }
        GlassCard {
            Row {
                Title("Цена для ученика", Modifier.weight(1f))
                Text(if (b.hasCustomPrice(app.me, studentId)) "своя" else "базовая", color = p.textSecondary, fontSize = 13.sp)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(price, { price = it.filter { c -> c.isDigit() } }, Modifier.weight(1f), suffix = { Text("₽ за час") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
                PrimaryButton("Сохранить", Modifier.width(130.dp)) { price.toIntOrNull()?.let { b.setPrice(app.me, studentId, it); app.info = "Цена сохранена: ${Fmt.rubles(it)}" } }
            }
            if (b.hasCustomPrice(app.me, studentId)) {
                TextButton({ b.setPrice(app.me, studentId, null); price = b.coachInfo(app.me).price.toString() }) {
                    Text("Вернуть базовую (${Fmt.rubles(b.coachInfo(app.me).price)})")
                }
            }
            Secondary("Новые записи этого ученика будут по этой цене. Другие ученики её не видят.")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton("📊 Статистика", Modifier.weight(1f)) { app.push(Route.StudentStats(studentId)) }
            SecondaryButton("📋 Упражнения", Modifier.weight(1f)) { app.push(Route.Exercises(studentId)) }
        }
        PrimaryButton("Написать ученику") { app.openChat(studentId) }
        Title("Тренировки")
        b.bookingsOfStudent(studentId).filter { it.coachId == app.me && it.status != BookingStatus.RESCHEDULED }.forEach {
            BookingRow(app, it, student?.name ?: "", if (it.status == BookingStatus.COMPLETED) (if (b.isEvaluated(it.id)) "Оценено" else "Нужно оценить") else null)
        }
    }
}

@Composable
fun MetricBar(title: String, value: Int) {
    val p = LocalPalette.current
    Column {
        Row { Text(title, Modifier.weight(1f), color = p.text, fontSize = 14.sp); Text("$value", fontWeight = FontWeight.Bold, color = p.text) }
        Box(Modifier.fillMaxWidth().height(6.dp).background(p.textSecondary.copy(alpha = 0.15f), RoundedCornerShape(3.dp))) {
            Box(Modifier.fillMaxWidth(value / 100f).height(6.dp).background(p.accent, RoundedCornerShape(3.dp)))
        }
    }
}

// endregion

// region Места

@Composable
fun VenuesScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    Screen("Места и расписание", app) {
        Secondary("Ученики видят свободное время только в местах, которые им открыты. Изменения сразу появляются в их календаре.", size = 14)
        b.venues(app.me).forEach { venue ->
            GlassCard(onClick = { app.push(Route.VenueEditor(venue.id)) }) {
                Row { Title(venue.name, Modifier.weight(1f)); Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary) }
                Secondary("📍 ${venue.address}")
                Text("🕒 ${venue.daysTitle} · ${venue.hoursTitle}", color = p.text, fontSize = 14.sp)
                val names = venue.allowed.mapNotNull { b.person(it)?.firstName }.sorted()
                Text(
                    if (venue.onlySelected) "🔒 Только: ${names.joinToString(", ").ifEmpty { "никто не выбран" }}" else "👥 Все ученики",
                    color = if (venue.onlySelected) p.pending else p.completed, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                )
            }
        }
        PrimaryButton("+ Добавить место") { app.push(Route.VenueEditor(null)) }
    }
}

@Composable
fun VenueEditorScreen(app: AppState, venueId: String?) {
    val p = LocalPalette.current
    val b = app.backend
    val existing = venueId?.let { b.venue(it) }
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var address by remember { mutableStateOf(existing?.address ?: "") }
    var weekdays by remember { mutableStateOf(existing?.weekdays ?: setOf(1, 2, 3, 4, 5)) }
    var hours by remember { mutableStateOf(existing?.hours?.toSet() ?: setOf(18, 19, 20)) }
    var onlySelected by remember { mutableStateOf(existing?.onlySelected ?: false) }
    var allowed by remember { mutableStateOf(existing?.allowed ?: emptySet()) }
    var confirmDelete by remember { mutableStateOf(false) }

    Screen(if (existing == null) "Новое место" else existing.name, app, bottom = {
        PrimaryButton("Сохранить", Modifier.padding(16.dp), enabled = name.isNotBlank()) {
            b.saveVenue(Venue(existing?.id ?: newId(), app.me, name.trim(), address.trim(), weekdays, hours.sorted(), onlySelected, allowed))
            app.pop()
        }
    }) {
        OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("Название, например «Флагман»") }, singleLine = true)
        OutlinedTextField(address, { address = it }, Modifier.fillMaxWidth(), label = { Text("Адрес") }, singleLine = true)
        Title("Дни")
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Venue.WEEKDAYS.forEachIndexed { index, title ->
                val d = index + 1
                Chip(title, d in weekdays, Modifier.weight(1f)) { weekdays = if (d in weekdays) weekdays - d else weekdays + d }
            }
        }
        Title("Начало тренировок")
        (0..23).chunked(4).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { h -> Chip("%02d:00".format(h), h in hours, Modifier.weight(1f)) { hours = if (h in hours) hours - h else hours + h } }
            }
        }
        Secondary("Каждая отмеченная клетка — свободный слот на 1 час в выбранные дни на 3 недели вперёд.")
        Title("Кто может записаться")
        Segmented(listOf(false, true), onlySelected, { if (it) "Только выбранные" else "Все ученики" }) { onlySelected = it }
        if (onlySelected) {
            b.students.forEach { s ->
                GlassCard(onClick = { allowed = if (s.id in allowed) allowed - s.id else allowed + s.id }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(b.person(s.id), 30.dp)
                        Spacer(Modifier.width(10.dp))
                        Text(b.name(s.id), Modifier.weight(1f), color = p.text)
                        Text(if (s.id in allowed) "✓" else "", color = p.accent, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    }
                }
            }
            Secondary("Остальные ученики не увидят это место и его время.")
        }
        if (existing != null) {
            SecondaryButton("Удалить место", Modifier.fillMaxWidth(), p.cancelled) { confirmDelete = true }
        }
        Spacer(Modifier.height(16.dp))
    }
    if (confirmDelete && existing != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Удалить «${existing.name}»?") },
            text = { Text("Свободные слоты исчезнут, записи останутся.") },
            confirmButton = { TextButton({ confirmDelete = false; b.deleteVenue(existing); app.pop() }) { Text("Удалить", color = p.cancelled) } },
            dismissButton = { TextButton({ confirmDelete = false }) { Text("Отмена") } },
        )
    }
}

// endregion

// region Групповые

@Composable
fun CoachGroupsScreen(app: AppState) {
    val b = app.backend
    Screen("Групповые", app, actions = {
        IconButton({ app.push(Route.GroupEditor) }) { Icon(Icons.Filled.Add, "Создать", tint = LocalPalette.current.accent) }
    }) {
        Secondary("Игровые и групповые тренировки: несколько учеников в одно время. Ученики записываются сами в «Календаре».", size = 14)
        val list = b.groupsOf(app.me)
        if (list.isEmpty()) Secondary("Пока нет запланированных групповых")
        list.forEach { GroupCard(app, it) }
        PrimaryButton("+ Создать групповую") { app.push(Route.GroupEditor) }
    }
}

@Composable
fun GroupEditorScreen(app: AppState) {
    val b = app.backend
    val venues = b.venues(app.me)
    var title by remember { mutableStateOf("Игровая тренировка") }
    var venueId by remember { mutableStateOf(venues.firstOrNull()?.id) }
    var day by remember { mutableStateOf(LocalDate.now().plusDays(2)) }
    var hour by remember { mutableStateOf(19) }
    var minutes by remember { mutableStateOf(120) }
    var capacity by remember { mutableStateOf(6) }
    var price by remember { mutableStateOf("1200") }
    Screen("Новая групповая", app, bottom = {
        PrimaryButton("Создать", Modifier.padding(16.dp), enabled = title.isNotBlank() && venueId != null) {
            app.run {
                b.createGroup(GroupSession(newId(), app.me, venueId!!, title.trim(), day.at(hour), minutes, capacity, price.toIntOrNull() ?: 0))
                app.pop()
            }
        }
    }) {
        OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("Название") }, singleLine = true)
        Title("Место")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            venues.forEach { v -> Chip(v.name, v.id == venueId) { venueId = v.id } }
        }
        Title("День")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (0L..20L).map { LocalDate.now().plusDays(it) }.forEach { d ->
                Chip("${Venue.WEEKDAYS[d.dayOfWeek.value - 1]}\n${d.dayOfMonth}", d == day) { day = d }
            }
        }
        Title("Начало")
        (10..22).chunked(5).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { h -> Chip("%02d:00".format(h), h == hour, Modifier.weight(1f)) { hour = h } }
                repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Title("Длительность")
        Segmented(listOf(60, 90, 120, 180), minutes, { if (it == 90) "1,5 ч" else "${it / 60} ч" }) { minutes = it }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Title("Мест: $capacity", Modifier.weight(1f))
            SecondaryButton("−") { if (capacity > 2) capacity-- }
            Spacer(Modifier.width(8.dp))
            SecondaryButton("+") { if (capacity < 20) capacity++ }
        }
        OutlinedTextField(price, { price = it.filter { c -> c.isDigit() } }, Modifier.fillMaxWidth(), label = { Text("Цена с человека") },
            suffix = { Text("₽") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true)
        Secondary("Свободные индивидуальные слоты в это время закроются. Ученики, которым открыто место, получат уведомление.")
    }
}

@Composable
fun GroupDetailScreen(app: AppState, groupId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val session = b.group(groupId) ?: return Screen("Групповая", app) { Secondary("Тренировка не найдена") }
    val venue = b.venue(session.venueId)
    val joined = app.me in session.participants
    var confirmCancel by remember { mutableStateOf(false) }
    Screen("Групповая", app) {
        Text("👥 ${session.title}", fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Title(Fmt.day(session.start))
        Secondary(Fmt.range(session.start, session.minutes), size = 16)
        GlassCard {
            Text("Тренер: ${b.name(session.coachId)}", color = p.text)
            Text("📍 ${venue?.name}, ${venue?.address}", color = p.text)
            Text("💳 ${Fmt.rubles(session.price)} с человека · оплата в клубе", color = p.text)
            Text("👥 Мест: ${session.participants.size} из ${session.capacity}", color = p.text)
        }
        if (app.isCoach || joined) {
            GlassCard {
                Title("Участники")
                if (session.participants.isEmpty()) Secondary("Пока никто не записался")
                session.participants.forEach { id ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(b.person(id), 32.dp)
                        Spacer(Modifier.width(10.dp))
                        Text(if (id == app.me) "Вы" else b.name(id), color = p.text)
                    }
                }
            }
        }
        when {
            app.isCoach -> SecondaryButton("Отменить групповую", Modifier.fillMaxWidth(), p.cancelled) { confirmCancel = true }
            joined -> SecondaryButton("Не смогу прийти", Modifier.fillMaxWidth(), p.cancelled) { b.leave(groupId, app.me) }
            else -> PrimaryButton(if (session.freePlaces > 0) "Записаться · ${Fmt.rubles(session.price)}" else "Мест нет", enabled = session.freePlaces > 0) {
                app.run { b.join(groupId, app.me) }
            }
        }
    }
    if (confirmCancel) {
        AlertDialog(
            onDismissRequest = { confirmCancel = false },
            title = { Text("Отменить тренировку?") },
            text = { Text("Участники получат сообщение.") },
            confirmButton = { TextButton({ confirmCancel = false; b.cancelGroup(groupId); app.pop() }) { Text("Отменить", color = p.cancelled) } },
            dismissButton = { TextButton({ confirmCancel = false }) { Text("Назад") } },
        )
    }
}

// endregion
