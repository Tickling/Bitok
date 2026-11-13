@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Запись ученика, подтверждение, карточка тренировки, оценка, обмен местами, предложение времени.
package app.bitok.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Domain
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Event
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate

// region Общие строки

@Composable
fun BookingRow(app: AppState, booking: Booking, title: String, subtitle: String? = null) {
    val p = LocalPalette.current
    GlassCard(onClick = { app.push(Route.BookingDetail(booking.id)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(4.dp).height(52.dp).background(statusColor(booking.status), RoundedCornerShape(2.dp)))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("${Fmt.shortDay(booking.start)} · ${Fmt.time(booking.start)} · $title", fontWeight = FontWeight.SemiBold, color = p.text)
                StatusPill(booking.status)
                subtitle?.let { Secondary(it) }
            }
            Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
        }
    }
}

@Composable
fun GroupCard(app: AppState, session: GroupSession, joined: Boolean = false) {
    val p = LocalPalette.current
    val b = app.backend
    GlassCard(onClick = { app.push(Route.GroupDetail(session.id)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(4.dp).height(64.dp).background(p.accent2, RoundedCornerShape(2.dp)))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("${Fmt.shortDay(session.start)} · ${Fmt.range(session.start, session.minutes)}", fontWeight = FontWeight.SemiBold, color = p.text)
                Text("👥 ${session.title}", fontWeight = FontWeight.Bold, color = p.text)
                Secondary("${b.venue(session.venueId)?.name ?: "Клуб"} · ${Fmt.rubles(session.price)}")
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("${session.participants.size} из ${session.capacity}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                        color = if (session.freePlaces == 0) p.cancelled else p.completed)
                    if (joined) Text("✓ Вы записаны", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.accent)
                }
            }
            Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
        }
    }
}

/** Сетка времени по 3 в ряд. */
@Composable
fun SlotGrid(app: AppState, slots: List<Slot>, selected: String?, showPlace: Boolean, onSelect: (Slot) -> Unit) {
    slots.chunked(3).forEach { row ->
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            row.forEach { slot ->
                val label = Fmt.time(slot.start) + if (showPlace) "\n" + (app.backend.venue(slot.venueId)?.name ?: "") else ""
                Chip(label, slot.id == selected, Modifier.weight(1f)) { onSelect(slot) }
            }
            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

/** Сетка ученика: свободное время + занятое другими (неактивно, «забронировано»); можно выбрать несколько часов подряд. */
@Composable
fun StudentSlotGrid(app: AppState, slots: List<Slot>, held: List<Slot>, selected: List<String>, showPlace: Boolean, onSelect: (Slot) -> Unit) {
    val p = LocalPalette.current
    val heldIds = held.map { it.id }.toSet()
    (slots + held).sortedBy { it.start }.chunked(3).forEach { row ->
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            row.forEach { slot ->
                if (slot.id in heldIds) {
                    Column(
                        Modifier.weight(1f).heightIn(min = 44.dp)
                            .background(p.textSecondary.copy(alpha = 0.12f), androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                            .padding(vertical = 6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(Fmt.time(slot.start), color = p.textSecondary, fontWeight = FontWeight.SemiBold,
                            textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough)
                        Text("забронировано", color = p.textSecondary, fontSize = 11.sp)
                    }
                } else {
                    val label = Fmt.time(slot.start) + if (showPlace) "\n" + (app.backend.venue(slot.venueId)?.name ?: "") else ""
                    Chip(label, slot.id in selected, Modifier.weight(1f)) { onSelect(slot) }
                }
            }
            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

/** Выбор подряд: соседний час того же места добавляется (до 3), крайний — убирается, остальное — новый выбор. */
fun toggleConsecutive(b: DemoBackend, selected: List<String>, slot: Slot): List<String> {
    val chosen = selected.mapNotNull { b.slot(it) }.sortedBy { it.start }
    if (slot.id in selected) {
        return if (slot.id == chosen.first().id || slot.id == chosen.last().id) selected - slot.id else listOf(slot.id)
    }
    val first = chosen.firstOrNull() ?: return listOf(slot.id)
    val last = chosen.last()
    return if (chosen.size < 3 && slot.venueId == first.venueId && (slot.start == last.end || slot.end == first.start)) selected + slot.id
    else listOf(slot.id)
}

// endregion

// region Запись ученика

@Composable
fun StudentBookingScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    val coachId = app.selectedCoach
    val me = app.me
    var month by remember { mutableStateOf(LocalDate.now().withDayOfMonth(1)) }
    var day by remember(coachId) { mutableStateOf<LocalDate?>(null) }
    var slotIds by remember(coachId) { mutableStateOf<List<String>>(emptyList()) }
    val info = b.coachInfo(coachId)
    // Скриншот «Помощи»: выбран ближайший день и первое время.
    androidx.compose.runtime.LaunchedEffect(app.uiPage) {
        if (app.uiPage == "day") {
            val first = b.availableDays(coachId, me).sorted().firstOrNull { d -> b.freeSlots(coachId, d, me).any { b.leadTime(it) > 600_000 } }
            if (first != null) {
                day = first
                kotlinx.coroutines.delay(300)
                slotIds = listOfNotNull(b.freeSlots(coachId, first, me).firstOrNull { b.leadTime(it) > 600_000 }?.id)
            }
            app.uiPage = null
        }
    }

    Screen("Запись", app, bottom = {
        val chosen = slotIds.mapNotNull { b.slot(it) }.sortedBy { it.start }
        if (chosen.isNotEmpty()) {
            val hours = if (chosen.size > 1) " · ${chosen.size} ч" else ""
            PrimaryButton("Продолжить · ${Fmt.time(chosen.first().start)}–${Fmt.time(chosen.last().end)}$hours", Modifier.padding(16.dp)) {
                app.push(Route.Confirm(chosen.map { it.id }))
            }
        }
    }) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            b.coaches.forEach { coach -> Chip(b.person(coach.id)?.firstName ?: coach.firstName, coach.id == coachId) { app.selectedCoach = coach.id } }
        }
        GlassCard(onClick = { app.push(Route.PersonProfile(coachId)) }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(b.person(coachId), 44.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(b.name(coachId), fontWeight = FontWeight.SemiBold, color = p.text)
                    Secondary(info.rank)
                    Secondary("📍 " + b.venues(coachId).filter { b.canBook(it.id, me) }.joinToString(" · ") { it.name })
                    Secondary("🕒 ${info.hours}")
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton({ month = month.minusMonths(1); day = null }) { Icon(Icons.Filled.ChevronLeft, "Предыдущий месяц", tint = p.accent) }
            Text(Fmt.monthYear(month), Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
            IconButton({ month = month.plusMonths(1); day = null }) { Icon(Icons.Filled.ChevronRight, "Следующий месяц", tint = p.accent) }
        }
        val myDays = b.bookingsOfStudent(me).filter { it.status.holdsSlot }.map { it.start.toDate() }.toSet()
        MonthGrid(month, day, b.availableDays(coachId, me), myDays) { day = it; slotIds = emptyList() }
        val selectedDay = day
        if (selectedDay == null) {
            Secondary("👆 Выберите день — доступные дни выделены", size = 15)
        } else {
            Title(Fmt.dayTitle(selectedDay))
            val slots = b.freeSlots(coachId, selectedDay, me)
            val held = b.heldSlots(coachId, selectedDay, me)
            if (slots.isEmpty() && held.isEmpty()) Secondary("На этот день свободного времени нет")
            StudentSlotGrid(app, slots, held, slotIds, slots.map { it.venueId }.toSet().size > 1) { slotIds = toggleConsecutive(b, slotIds, it) }
            if (slots.isNotEmpty()) {
                Secondary(if (slotIds.size == 1) "Нажмите на соседнее время, чтобы взять 2 часа подряд" else "Можно выбрать до 3 часов подряд", size = 13)
            }
        }
        val groups = b.openGroups(coachId, me)
        if (groups.isNotEmpty()) {
            Title("Групповые тренировки")
            groups.forEach { GroupCard(app, it, me in it.participants) }
        }
        val all = b.bookingsOfStudent(me)
        val upcoming = all.filter { it.status.holdsSlot }.sortedBy { it.start }
        if (upcoming.isNotEmpty()) {
            Title("Мои записи")
            Secondary("Нажмите на запись, чтобы отменить или перенести")
            upcoming.forEach { BookingRow(app, it, b.name(it.coachId)) }
        }
        val past = all.filter { !it.status.holdsSlot && it.status != BookingStatus.RESCHEDULED }.take(5)
        if (past.isNotEmpty()) {
            Title("Прошедшие")
            past.forEach { BookingRow(app, it, b.name(it.coachId), if (b.isEvaluated(it.id)) "Есть оценка тренера" else null) }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
fun ConfirmBookingScreen(app: AppState, slotIds: List<String>) {
    val b = app.backend
    val chosen = slotIds.mapNotNull { b.slot(it) }.sortedBy { it.start }
    val slot = chosen.firstOrNull()?.takeIf { chosen.size == slotIds.size } ?: return Screen("Запись", app) { Secondary("Слот уже заняли") }
    val minutes = chosen.sumOf { it.minutes }
    var comment by remember { mutableStateOf("") }
    var isGroup by remember { mutableStateOf(false) }
    Screen("Проверьте запись", app, bottom = {
        PrimaryButton("Записаться", Modifier.padding(16.dp)) {
            app.run {
                val text = comment.trim()
                var note = if (isGroup) "👥 Групповая тренировка" + (if (text.isEmpty()) "" else ". $text") else text
                if (chosen.size > 1) note = "${chosen.size} часа подряд" + (if (note.isEmpty()) "" else ". $note")
                chosen.forEach { item ->
                    val booking = b.book(item.id, app.me, note.ifEmpty { null })
                    if (isGroup) b.markGroup(booking.id)
                }
                app.openChat(slot.coachId)
            }
        }
    }) {
        GlassCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(b.person(slot.coachId), 44.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Secondary("Тренер")
                    Title(b.name(slot.coachId))
                }
            }
            InfoRow(Icons.Filled.CalendarMonth, Fmt.day(slot.start))
            InfoRow(Icons.Filled.AccessTime, Fmt.range(slot.start, minutes) + if (chosen.size > 1) " · ${chosen.size} ч подряд" else "")
            InfoRow(Icons.Filled.Place, b.place(slot.id))
            InfoRow(Icons.Filled.Domain, b.address(slot.id))
            InfoRow(Icons.Filled.Payments, "${Fmt.rubles(b.price(slot.coachId, app.me) * chosen.size)} · оплата в клубе")
        }
        GlassCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("👥 Запись на групповую тренировку", Modifier.weight(1f), color = LocalPalette.current.text)
                androidx.compose.material3.Switch(isGroup, { isGroup = it })
            }
            Secondary("Тренер увидит, что вы хотите заниматься в группе (игровая тренировка с другими учениками).")
        }
        Title("Комментарий тренеру")
        OutlinedTextField(comment, { comment = it }, Modifier.fillMaxWidth(), placeholder = { Text("Например: хочу поработать над выходом") }, minLines = 2)
        Secondary("Тренер подтвердит заявку — статус будет виден в чате с ним", size = 14)
    }
}

// endregion

// region Карточка тренировки

@Composable
fun BookingDetailScreen(app: AppState, bookingId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val booking = b.booking(bookingId) ?: return Screen("Тренировка", app) { Secondary("Запись не найдена") }
    val isCoach = app.isCoach
    val other = b.person(if (isCoach) booking.studentId else booking.coachId)
    var confirmCancel by remember { mutableStateOf(false) }

    Screen("Тренировка", app) {
        StatusPill(booking.status)
        Text(Fmt.day(booking.start), fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Secondary(Fmt.range(booking.start, booking.minutes), size = 18)
        GlassCard(onClick = { other?.let { app.push(Route.PersonProfile(it.id)) } }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(other, 48.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Secondary(if (isCoach) "Ученик" else "Тренер")
                    Title(other?.name ?: "")
                    if (isCoach || b.bookingsOfStudent(app.me).any { it.coachId == booking.coachId }) {
                        Text("📞 ${other?.phone}", color = p.accent, fontSize = 14.sp)
                    }
                }
            }
        }
        GlassCard {
            InfoRow(Icons.Filled.Place, b.place(booking.slotId))
            InfoRow(Icons.Filled.Domain, b.address(booking.slotId))
            InfoRow(Icons.Filled.Payments, "${booking.minutes} мин · ${Fmt.rubles(booking.price)} · оплата в клубе")
            booking.comment?.let { InfoRow(Icons.Filled.Event, "«$it»") }
        }
        b.evaluation(booking.id)?.let { e ->
            GlassCard {
                Title("Оценка тренера")
                Metric.entries.forEach { m ->
                    Row { Text(m.title, Modifier.weight(1f), color = p.text); Text("${e.scores[m.name] ?: 0}", fontWeight = FontWeight.Bold, color = p.text) }
                }
                e.comment?.let { Secondary("«$it»") }
            }
        }
        val now = System.currentTimeMillis()
        if (isCoach) {
            if (booking.status == BookingStatus.AWAITING) {
                PrimaryButton("Подтвердить заявку") { app.run { b.approve(booking.id) } }
                SecondaryButton("Отклонить", Modifier.fillMaxWidth(), p.cancelled) { app.run { b.reject(booking.id) } }
            }
            if (booking.status == BookingStatus.AWAITING || (booking.status == BookingStatus.CONFIRMED && booking.start > now)) {
                SecondaryButton("Предложить другое время", Modifier.fillMaxWidth(), icon = Icons.Filled.Event) {
                    app.push(Route.Propose(booking.studentId, booking.id))
                }
            }
            if (b.swapCandidates(booking.id).isNotEmpty()) {
                SecondaryButton("Поменять местами с другим учеником", Modifier.fillMaxWidth(), icon = Icons.Filled.SwapHoriz) {
                    app.push(Route.Swap(booking.id))
                }
            }
            if (booking.status == BookingStatus.CONFIRMED) {
                PrimaryButton("Завершить тренировку (демо)") { app.run { b.complete(booking.id) } }
                SecondaryButton("Отметить неявку (демо)", Modifier.fillMaxWidth()) { app.run { b.noShow(booking.id) } }
                SecondaryButton("Отменить тренировку", Modifier.fillMaxWidth(), p.cancelled) { confirmCancel = true }
            }
            if (booking.status == BookingStatus.COMPLETED && !b.isEvaluated(booking.id)) {
                PrimaryButton("Оценить ученика") { app.push(Route.Evaluate(booking.id)) }
            }
            SecondaryButton("Написать ученику", Modifier.fillMaxWidth()) { app.openChat(booking.studentId) }
        } else {
            if (booking.status.holdsSlot) {
                PrimaryButton("Отменить запись") { confirmCancel = true }
                SecondaryButton("Перенести на другое время", Modifier.fillMaxWidth(), icon = Icons.Filled.SwapHoriz) {
                    app.run {
                        b.cancel(booking.id, app.me)
                        app.openBooking(booking.coachId)
                    }
                }
            }
            SecondaryButton("Написать тренеру", Modifier.fillMaxWidth()) { app.openChat(booking.coachId) }
        }
    }
    if (confirmCancel) {
        val late = booking.status == BookingStatus.CONFIRMED && booking.start - System.currentTimeMillis() < 12 * 3_600_000
        AlertDialog(
            onDismissRequest = { confirmCancel = false },
            title = { Text("Отменить тренировку?") },
            text = { Text(if (late) "До тренировки меньше 12 часов — отмена будет считаться поздней." else "Слот освободится, другая сторона получит уведомление.") },
            confirmButton = { TextButton({ confirmCancel = false; app.run { b.cancel(booking.id, app.me) } }) { Text("Отменить", color = p.cancelled) } },
            dismissButton = { TextButton({ confirmCancel = false }) { Text("Не отменять") } },
        )
    }
}

@Composable
fun EvaluateScreen(app: AppState, bookingId: String) {
    val b = app.backend
    val booking = b.booking(bookingId) ?: return
    val current = b.progress(booking.studentId)
    val scores = remember { mutableStateMapOf<Metric, Int>().apply { Metric.entries.forEach { put(it, current[it] ?: 50) } } }
    var comment by remember { mutableStateOf("") }
    val made = remember { mutableStateMapOf<String, Int>() }
    Screen("Оценка: ${b.person(booking.studentId)?.firstName}", app, bottom = {
        PrimaryButton("Сохранить оценку", Modifier.padding(16.dp)) {
            app.run {
                // Результаты упражнений → процент попаданий по метрике заменяет значение слайдера.
                val results = made.mapNotNull { (id, m) -> b.exercise(id)?.let { ExerciseResult(newId(), booking.studentId, booking.coachId, id, m, it.attempts, System.currentTimeMillis()) } }
                val final = scores.toMutableMap()
                results.groupBy { b.exercise(it.exerciseId)?.metric ?: Metric.AIMING }.forEach { (metric, items) -> final[metric] = items.sumOf { it.percent } / items.size }
                b.addResults(results)
                b.evaluate(bookingId, final, comment.trim().ifEmpty { null })
                app.pop()
            }
        }
    }) {
        GlassCard {
            Title("Упражнения на тренировке")
            Secondary("Отметьте выполненные упражнения и сколько забито — навыки пересчитаются по результатам.")
            ExerciseResultsEditor(app, made)
        }
        Metric.entries.forEach { m ->
            GlassCard {
                Row { Text(m.title, Modifier.weight(1f), color = LocalPalette.current.text); Text("${scores[m]}", fontWeight = FontWeight.Bold) }
                Slider(value = (scores[m] ?: 0).toFloat(), onValueChange = { scores[m] = it.toInt() }, valueRange = 0f..100f)
            }
        }
        OutlinedTextField(comment, { comment = it }, Modifier.fillMaxWidth(), placeholder = { Text("Комментарий и домашнее задание") }, minLines = 3)
    }
}

@Composable
fun SwapScreen(app: AppState, bookingId: String) {
    val b = app.backend
    val source = b.booking(bookingId) ?: return
    var selected by remember { mutableStateOf<String?>(null) }
    Screen("Поменять местами", app) {
        Title("${b.name(source.studentId)} · ${Fmt.shortDay(source.start)} ${Fmt.time(source.start)}")
        Secondary("Выберите, с кем поменять время. Оба ученика получат сообщение в чате.", size = 14)
        b.swapCandidates(bookingId).forEach { other ->
            GlassCard(onClick = { selected = other.id }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(b.person(other.studentId), 40.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Title(b.name(other.studentId))
                        Secondary("${Fmt.shortDay(other.start)} · ${Fmt.time(other.start)}")
                    }
                    Text(if (selected == other.id) "●" else "○", fontSize = 22.sp, color = LocalPalette.current.accent)
                }
            }
        }
        val other = selected?.let { b.booking(it) }
        if (other != null) {
            GlassCard {
                Secondary("После обмена")
                Text("${b.name(source.studentId)} → ${Fmt.time(other.start)}", fontWeight = FontWeight.SemiBold)
                Text("${b.name(other.studentId)} → ${Fmt.time(source.start)}", fontWeight = FontWeight.SemiBold)
            }
            PrimaryButton("Поменять местами") {
                app.run {
                    b.swap(source.id, other.id, app.me)
                    app.pop()
                    app.pop()
                }
            }
        }
    }
}

/** Тренер предлагает время ученику (или отвечает на заявку своим временем). */
@Composable
fun ProposeSlotScreen(app: AppState, studentId: String, replacing: String?) {
    val b = app.backend
    val coachId = app.me
    val days = b.availableDays(coachId).filter { it <= LocalDate.now().plusDays(14) }.sorted()
    var day by remember { mutableStateOf<LocalDate?>(null) }
    var slotId by remember { mutableStateOf<String?>(null) }
    var comment by remember { mutableStateOf("") }
    Screen(if (replacing == null) "Предложить время" else "Другое время", app, bottom = {
        PrimaryButton("Предложить ученику", Modifier.padding(16.dp), enabled = slotId != null) {
            val id = slotId ?: return@PrimaryButton
            app.run {
                val text = comment.trim().ifEmpty { null }
                if (replacing != null) b.counterPropose(replacing, id, text) else b.proposeSlot(coachId, studentId, id, text)
                app.pop()
            }
        }
    }) {
        Title("Для: ${b.name(studentId)}")
        replacing?.let { b.booking(it) }?.let {
            Secondary("Вместо ${Fmt.shortDay(it.start)}, ${Fmt.time(it.start)} — текущая заявка закроется")
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            days.forEach { d ->
                Chip("${Venue.WEEKDAYS[d.dayOfWeek.value - 1]}\n${d.dayOfMonth}", d == day) { day = d; slotId = null }
            }
        }
        val selectedDay = day
        if (selectedDay == null) Secondary("Выберите день")
        else SlotGrid(app, b.freeSlots(coachId, selectedDay), slotId, true) { slotId = it.id }
        OutlinedTextField(comment, { comment = it }, Modifier.fillMaxWidth(), placeholder = { Text("Комментарий: например, отработаем выход") })
    }
}

// endregion
