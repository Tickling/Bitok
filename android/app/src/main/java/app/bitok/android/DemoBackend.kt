// Локальный «сервер» для тестирования на одном телефоне: ученик и тренеры работают с общими данными.
// Правила те же, что в iOS-версии и в backend (ANALYTICS.md): статусы брони, 2 часа до начала, лимит заявок,
// места с доступом, индивидуальные цены, групповые тренировки.
package app.bitok.android

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.Json
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.UUID

class DemoError(message: String) : Exception(message)

enum class InvitationAnswer { ACCEPT, DECLINE, OTHER_TIME }

val zone: ZoneId get() = ZoneId.systemDefault()
fun LocalDate.at(hour: Int): Long = atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()
fun Long.toDate(): LocalDate = Instant.ofEpochMilli(this).atZone(zone).toLocalDate()
fun Long.hour(): Int = Instant.ofEpochMilli(this).atZone(zone).hour
fun newId(): String = UUID.randomUUID().toString()

class DemoBackend(private val prefs: SharedPreferences) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var state by mutableStateOf(DemoState())
        private set

    val coaches = listOf(
        Person(Ids.ALEXEY, "Алексей Воронов", "+7 900 000-00-01"),
        Person(Ids.VERONIKA, "Вероника Смирнова", "+7 900 000-00-03"),
    )
    private val baseInfo = mapOf(
        Ids.ALEXEY to CoachInfo("Мастер спорта", "Пн–Сб 16:00–22:00, Вс 12:00–16:00", "Русский бильярд, 15 лет тренерского опыта", 2500),
        Ids.VERONIKA to CoachInfo("КМС, тренер по пулу", "Пн, Ср, Пт, Вс 10:00–15:00", "Пул и постановка удара с нуля", 2000),
    )
    val students = listOf(
        Person(Ids.IVAN, "Иван Петров", "+7 900 000-00-02"),
        Person(Ids.MARIA, "Мария Соколова", "+7 916 555-01-21"),
        Person(Ids.OLEG, "Олег Морозов", "+7 903 555-01-02"),
        Person(Ids.ANNA, "Анна Романова", "+7 925 555-03-04"),
        Person(Ids.NATASHA, "Наталья Белова", "+7 900 000-00-04"),
    )

    init {
        val saved = prefs.getString(KEY, null)
        val restored = saved?.let { runCatching { json.decodeFromString(DemoState.serializer(), it) }.getOrNull() }
        if (restored != null) state = restored else seed()
    }

    private fun update(block: (DemoState) -> DemoState) {
        state = block(state)
        prefs.edit().putString(KEY, json.encodeToString(DemoState.serializer(), state)).apply()
    }

    private fun now() = System.currentTimeMillis()

    // region Люди

    fun isCoach(id: String) = coaches.any { it.id == id }

    fun person(id: String): Person? {
        val base = coaches.firstOrNull { it.id == id } ?: students.firstOrNull { it.id == id } ?: return null
        val edited = state.profiles[id]?.fullName?.takeIf { it.isNotBlank() } ?: return base
        return base.copy(name = edited)
    }

    fun name(id: String) = person(id)?.name ?: "Ученик"

    fun profile(id: String): Profile = state.profiles[id] ?: run {
        val parts = (coaches + students).firstOrNull { it.id == id }?.name.orEmpty().split(" ")
        Profile(parts.firstOrNull().orEmpty(), parts.drop(1).joinToString(" "), "Москва",
            if (id == Ids.VERONIKA) "Пул" else "Русский бильярд", "")
    }

    fun updateProfile(id: String, profile: Profile) = update { it.copy(profiles = it.profiles + (id to profile)) }

    fun coachInfo(id: String): CoachInfo = state.coachInfo[id] ?: baseInfo.getValue(id)

    fun updateCoachInfo(id: String, info: CoachInfo) = update { it.copy(coachInfo = it.coachInfo + (id to info)) }

    /** Ученики тренера: с бронями у него или перепиской. */
    fun studentsOf(coachId: String): List<Person> = students.filter { s ->
        state.bookings.any { it.studentId == s.id && it.coachId == coachId } ||
            state.messages.any { (it.from == s.id && it.to == coachId) || (it.from == coachId && it.to == s.id) }
    }.map { person(it.id) ?: it }

    // endregion

    // region Места

    fun venues(coachId: String) = state.venues.filter { it.coachId == coachId }
    fun venue(id: String) = state.venues.firstOrNull { it.id == id }
    fun place(slotId: String): String {
        val slot = slot(slotId) ?: return "Клуб"
        return "${venue(slot.venueId)?.name ?: "Клуб"}, стол ${slot.table}"
    }
    fun address(slotId: String) = slot(slotId)?.let { venue(it.venueId)?.address }.orEmpty()

    fun canBook(venueId: String, studentId: String): Boolean {
        val venue = venue(venueId) ?: return true
        return !venue.onlySelected || studentId in venue.allowed
    }

    fun saveVenue(venue: Venue) {
        update { s -> s.copy(venues = if (s.venues.any { it.id == venue.id }) s.venues.map { if (it.id == venue.id) venue else it } else s.venues + venue) }
        regenerate(venue.coachId)
    }

    fun deleteVenue(venue: Venue) {
        update { s -> s.copy(venues = s.venues.filterNot { it.id == venue.id }) }
        regenerate(venue.coachId)
    }

    /** Пересобрать будущие свободные слоты тренера по правилам мест. Занятые не трогаются. */
    fun regenerate(coachId: String) = update { s ->
        val kept = s.slots.filterNot { it.coachId == coachId && it.status == SlotStatus.AVAILABLE && it.start > now() }
        s.copy(slots = kept + generate(coachId, s.copy(slots = kept), fromDay = 0))
    }

    private fun generate(coachId: String, s: DemoState, fromDay: Int): List<Slot> {
        val today = LocalDate.now()
        val created = mutableListOf<Slot>()
        s.venues.filter { it.coachId == coachId }.forEachIndexed { venueIndex, venue ->
            val range = if (venue.isTest) maxOf(fromDay, 0)..7 else fromDay..21
            for (offset in range) {
                val day = today.plusDays(offset.toLong())
                if (day.dayOfWeek.value !in venue.weekdays) continue
                for (hour in venue.hours.sorted()) {
                    val start = day.at(hour)
                    if ((fromDay >= 0 || venue.isTest) && start <= now()) continue
                    val taken = (s.slots + created).any { it.coachId == coachId && it.start == start } ||
                        s.groups.any { g -> g.coachId == coachId && !g.cancelled && g.start < start + 3_600_000 && start < g.end }
                    if (taken) continue
                    created += Slot(newId(), coachId, venue.id, (hour + venueIndex) % 4 + 1, start)
                }
            }
        }
        return created
    }

    // endregion

    // region Слоты и брони

    fun slot(id: String) = state.slots.firstOrNull { it.id == id }
    fun booking(id: String) = state.bookings.firstOrNull { it.id == id }

    private fun bookable(slot: Slot) = slot.status == SlotStatus.AVAILABLE

    /** Сколько минимум до начала можно записаться: 2 часа, в тест-зале — 5 минут. */
    fun leadTime(slot: Slot): Long = if (venue(slot.venueId)?.isTest == true) 5 * 60_000L else 2 * 3_600_000L

    fun freeSlots(coachId: String, day: LocalDate, studentId: String? = null): List<Slot> =
        state.slots.filter {
            it.coachId == coachId && it.start.toDate() == day && bookable(it) && it.start - now() >= leadTime(it) &&
                (studentId == null || canBook(it.venueId, studentId))
        }.sortedBy { it.start }

    fun availableDays(coachId: String, studentId: String? = null): Set<LocalDate> =
        state.slots.filter {
            it.coachId == coachId && bookable(it) && it.start - now() >= leadTime(it) &&
                (studentId == null || canBook(it.venueId, studentId))
        }.map { it.start.toDate() }.toSet()

    fun coachFreeSlots(coachId: String, day: LocalDate) =
        state.slots.filter { it.coachId == coachId && it.start.toDate() == day && bookable(it) && it.start > now() }.sortedBy { it.start }

    fun bookingsOfStudent(id: String) = state.bookings.filter { it.studentId == id }.sortedByDescending { it.start }

    fun bookingsOf(coachId: String, day: LocalDate) =
        state.bookings.filter { it.coachId == coachId && it.start.toDate() == day && it.status != BookingStatus.RESCHEDULED }.sortedBy { it.start }

    fun pendingRequests(coachId: String) =
        state.bookings.filter { it.coachId == coachId && it.status == BookingStatus.AWAITING }.sortedBy { it.start }

    fun isEvaluated(bookingId: String) = state.evaluations.any { it.bookingId == bookingId }
    fun evaluation(bookingId: String) = state.evaluations.firstOrNull { it.bookingId == bookingId }

    fun price(coachId: String, studentId: String): Int = state.studentPrices["$coachId|$studentId"] ?: coachInfo(coachId).price
    fun hasCustomPrice(coachId: String, studentId: String) = state.studentPrices.containsKey("$coachId|$studentId")
    fun setPrice(coachId: String, studentId: String, rubles: Int?) = update {
        val key = "$coachId|$studentId"
        it.copy(studentPrices = if (rubles == null) it.studentPrices - key else it.studentPrices + (key to rubles))
    }

    private fun overlaps(studentId: String, start: Long, end: Long, ignoring: String? = null) =
        state.bookings.any { it.id != ignoring && it.studentId == studentId && it.status.holdsSlot && it.start < end && start < it.end }

    fun book(slotId: String, studentId: String, comment: String?): Booking {
        val slot = slot(slotId)?.takeIf { bookable(it) } ?: throw DemoError("Этот слот уже заняли. Выберите другое время.")
        if (slot.start - now() < leadTime(slot)) throw DemoError("Записаться можно не позднее чем за ${leadTime(slot) / 60_000} мин до начала.")
        if (!canBook(slot.venueId, studentId)) throw DemoError("Это место доступно только ученикам тренера по приглашению.")
        if (state.bookings.count { it.studentId == studentId && it.status == BookingStatus.AWAITING } >= 3) {
            throw DemoError("У вас уже 3 заявки ждут тренера.")
        }
        if (overlaps(studentId, slot.start, slot.end)) throw DemoError("У вас уже есть тренировка в это время.")
        val booking = Booking(newId(), slot.id, studentId, slot.coachId, slot.start, slot.minutes, price(slot.coachId, studentId),
            BookingStatus.AWAITING, comment, now())
        update { s ->
            s.copy(
                slots = s.slots.map { if (it.id == slot.id) it.copy(status = SlotStatus.HELD) else it },
                bookings = s.bookings + booking,
            )
        }
        notify(booking.coachId, "Новая заявка", "${name(studentId)} · ${Fmt.stamp(booking.start)}")
        post(studentId, booking.coachId, comment?.let { "Заявка на тренировку. $it" } ?: "Заявка на тренировку", booking.id)
        return booking
    }

    private fun setStatus(id: String, status: BookingStatus, slotStatus: SlotStatus?) {
        val booking = booking(id) ?: throw DemoError("Запись не найдена")
        update { s ->
            s.copy(
                bookings = s.bookings.map { if (it.id == id) it.copy(status = status) else it },
                slots = if (slotStatus == null) s.slots else s.slots.map { if (it.id == booking.slotId) it.copy(status = slotStatus) else it },
            )
        }
    }

    private fun require(id: String, vararg allowed: BookingStatus): Booking {
        val booking = booking(id) ?: throw DemoError("Запись не найдена")
        if (booking.status !in allowed) throw DemoError("Это действие недоступно в текущем статусе.")
        return booking
    }

    fun approve(id: String) {
        val b = require(id, BookingStatus.AWAITING)
        setStatus(id, BookingStatus.CONFIRMED, SlotStatus.BOOKED)
        notifier?.remind(b)
        notify(b.studentId, "Тренировка подтверждена ✓", "${name(b.coachId)} · ${Fmt.stamp(b.start)}")
        post(b.coachId, b.studentId, "Тренировка подтверждена ✓ Жду вас!", id)
    }

    fun reject(id: String, note: String? = null) {
        val b = require(id, BookingStatus.AWAITING)
        setStatus(id, BookingStatus.REJECTED, SlotStatus.AVAILABLE)
        notify(b.studentId, "Заявка отклонена", Fmt.stamp(b.start))
        post(b.coachId, b.studentId, note ?: "Заявка отклонена: неудобное время. Выберите другое время", id)
    }

    fun cancel(id: String, actor: String) {
        val b = require(id, BookingStatus.AWAITING, BookingStatus.CONFIRMED)
        val byCoach = isCoach(actor)
        setStatus(id, if (byCoach) BookingStatus.CANCELLED_BY_COACH else BookingStatus.CANCELLED_BY_STUDENT, SlotStatus.AVAILABLE)
        notifier?.cancelReminder(id)
        val target = if (byCoach) b.studentId else b.coachId
        notify(target, "Тренировка отменена", "${name(actor)} · ${Fmt.stamp(b.start)}")
        post(actor, target, "Тренировка отменена", id)
    }

    /** Демо: «время тренировки наступило» — завершаем, даже если по часам она ещё впереди. */
    fun complete(id: String) {
        val b = require(id, BookingStatus.CONFIRMED)
        setStatus(id, BookingStatus.COMPLETED, null)
        notify(b.studentId, "Тренировка завершена", "Тренер скоро оценит ваши навыки")
        post(b.coachId, b.studentId, "Спасибо за тренировку! Скоро пришлю оценку", id)
    }

    fun noShow(id: String) {
        require(id, BookingStatus.CONFIRMED)
        setStatus(id, BookingStatus.NO_SHOW, null)
    }

    fun evaluate(bookingId: String, scores: Map<Metric, Int>, comment: String?) {
        val b = require(bookingId, BookingStatus.COMPLETED)
        val before = progress(b.studentId)
        val evaluation = Evaluation(bookingId, b.studentId, b.coachId, scores.mapKeys { it.key.name }, comment, now())
        update { s -> s.copy(evaluations = s.evaluations.filterNot { it.bookingId == bookingId } + evaluation) }
        val after = progress(b.studentId)
        val deltas = Metric.entries.mapNotNull { m ->
            val d = (after[m] ?: 0) - (before[m] ?: 0)
            if (d != 0) "${m.title} ${if (d > 0) "+" else ""}$d" else null
        }
        notify(b.studentId, "Новая оценка тренера", deltas.joinToString(" · ").ifEmpty { "Откройте «Прогресс»" })
        post(b.coachId, b.studentId, "Оценка тренировки: " + deltas.joinToString(", ").ifEmpty { "смотрите «Прогресс»" }, bookingId)
    }

    // endregion

    // region Предложение времени, обмен местами

    fun proposeSlot(coachId: String, studentId: String, slotId: String, comment: String?) {
        val slot = slot(slotId) ?: throw DemoError("Слот не найден")
        if (slot.coachId != coachId) throw DemoError("Нет прав на это действие.")
        if (!bookable(slot)) throw DemoError("Этот слот уже заняли. Выберите другое время.")
        val message = Message(newId(), coachId, studentId, "Предлагаю тренировку", now(),
            invitation = Invitation(slotId, InvitationStatus.SENT, comment))
        update { it.copy(messages = it.messages + message) }
        notify(studentId, "${name(coachId)} предлагает тренировку", Fmt.stamp(slot.start))
    }

    /** Ответ на заявку своим временем: заявка закрывается, ученику уходит предложение. */
    fun counterPropose(bookingId: String, slotId: String, comment: String?) {
        val b = booking(bookingId) ?: throw DemoError("Запись не найдена")
        val slot = slot(slotId)?.takeIf { bookable(it) } ?: throw DemoError("Этот слот уже заняли.")
        when (b.status) {
            BookingStatus.AWAITING -> reject(bookingId, "В ${Fmt.time(b.start)} не получится — предлагаю другое время 👇")
            BookingStatus.CONFIRMED -> cancel(bookingId, b.coachId)
            else -> Unit
        }
        proposeSlot(b.coachId, b.studentId, slot.id, comment)
    }

    fun answerInvitation(messageId: String, studentId: String, answer: InvitationAnswer) {
        val message = state.messages.firstOrNull { it.id == messageId && it.to == studentId } ?: throw DemoError("Нет прав на это действие.")
        val invitation = message.invitation ?: return
        if (invitation.status != InvitationStatus.SENT) return
        val coachId = message.from
        var updated = invitation
        when (answer) {
            InvitationAnswer.ACCEPT -> {
                val slot = slot(invitation.slotId)?.takeIf { bookable(it) } ?: throw DemoError("Этот слот уже заняли.")
                if (overlaps(studentId, slot.start, slot.end)) throw DemoError("У вас уже есть тренировка в это время.")
                val booking = Booking(newId(), slot.id, studentId, coachId, slot.start, slot.minutes, price(coachId, studentId),
                    BookingStatus.CONFIRMED, null, now())
                update { s ->
                    s.copy(slots = s.slots.map { if (it.id == slot.id) it.copy(status = SlotStatus.BOOKED) else it }, bookings = s.bookings + booking)
                }
                updated = invitation.copy(status = InvitationStatus.ACCEPTED, bookingId = booking.id)
                notifier?.remind(booking)
                post(studentId, coachId, "Принимаю предложение ✓", booking.id)
                notify(coachId, "${name(studentId)} принял предложение", Fmt.stamp(booking.start))
            }
            InvitationAnswer.DECLINE -> {
                updated = invitation.copy(status = InvitationStatus.DECLINED)
                post(studentId, coachId, "Не смогу в это время")
            }
            InvitationAnswer.OTHER_TIME -> {
                updated = invitation.copy(status = InvitationStatus.OTHER_TIME)
                post(studentId, coachId, "Это время не подходит — выберу другое в календаре")
            }
        }
        update { s -> s.copy(messages = s.messages.map { if (it.id == messageId) it.copy(invitation = updated) else it }) }
    }

    fun swapCandidates(bookingId: String): List<Booking> {
        val source = booking(bookingId)?.takeIf { it.status == BookingStatus.CONFIRMED && it.start > now() } ?: return emptyList()
        return state.bookings.filter {
            it.id != source.id && it.coachId == source.coachId && it.studentId != source.studentId &&
                it.status == BookingStatus.CONFIRMED && it.start > now()
        }.sortedWith(compareBy({ it.start.toDate() != source.start.toDate() }, { it.start }))
    }

    /** Тренер меняет двух учеников местами: каждому — подтверждённая запись на время другого. */
    fun swap(firstId: String, secondId: String, coachId: String) {
        val first = require(firstId, BookingStatus.CONFIRMED)
        val second = require(secondId, BookingStatus.CONFIRMED)
        if (first.coachId != coachId || second.coachId != coachId) throw DemoError("Нет прав на это действие.")
        if (overlaps(first.studentId, second.start, second.end, ignoring = first.id) ||
            overlaps(second.studentId, first.start, first.end, ignoring = second.id)
        ) throw DemoError("У ученика уже есть тренировка в это время.")
        val firstNew = first.copy(id = newId(), slotId = second.slotId, start = second.start, minutes = second.minutes, createdAt = now())
        val secondNew = second.copy(id = newId(), slotId = first.slotId, start = first.start, minutes = first.minutes, createdAt = now())
        update { s ->
            s.copy(bookings = s.bookings.map { if (it.id == first.id || it.id == second.id) it.copy(status = BookingStatus.RESCHEDULED) else it } +
                listOf(firstNew, secondNew))
        }
        listOf(first to firstNew, second to secondNew).forEach { (old, new) -> notifier?.cancelReminder(old.id); notifier?.remind(new) }
        for ((old, new, partner) in listOf(Triple(first, firstNew, second.studentId), Triple(second, secondNew, first.studentId))) {
            post(coachId, old.studentId, "Поменял вас местами с ${person(partner)?.firstName}: теперь ${Fmt.stamp(new.start)} вместо ${Fmt.time(old.start)}", new.id)
            notify(old.studentId, "Время тренировки изменено", "${Fmt.stamp(new.start)} вместо ${Fmt.time(old.start)}")
        }
    }

    // endregion

    // region Прогресс

    /** Текущие навыки: последняя оценка, смешанная с предыдущим уровнем (70/30). */
    fun progress(studentId: String): Map<Metric, Int> {
        var current = emptyMap<Metric, Int>()
        for (e in state.evaluations.filter { it.studentId == studentId }.sortedBy { it.at }) {
            current = Metric.entries.associateWith { m ->
                val new = e.scores[m.name] ?: current[m] ?: 0
                current[m]?.let { (it * 0.3 + new * 0.7).toInt() } ?: new
            }
        }
        return current
    }

    fun history(studentId: String): List<Pair<Long, Int>> {
        val result = mutableListOf<Pair<Long, Int>>()
        var current = emptyMap<Metric, Int>()
        for (e in state.evaluations.filter { it.studentId == studentId }.sortedBy { it.at }) {
            current = Metric.entries.associateWith { m ->
                val new = e.scores[m.name] ?: current[m] ?: 0
                current[m]?.let { (it * 0.3 + new * 0.7).toInt() } ?: new
            }
            result += e.at to current.values.average().toInt()
        }
        return result
    }

    fun rating(studentId: String): Int? = progress(studentId).takeIf { it.isNotEmpty() }?.values?.average()?.toInt()

    fun level(rating: Int?): String = when {
        rating == null -> "Новичок"
        rating < 30 -> "Новичок"
        rating < 50 -> "Любитель"
        rating < 70 -> "Продвинутый"
        rating < 85 -> "Эксперт"
        else -> "Мастер"
    }

    fun setPrivacy(privacy: Privacy) = update { it.copy(privacy = privacy) }

    // endregion

    // region Чат и уведомления

    fun conversation(a: String, b: String) =
        state.messages.filter { (it.from == a && it.to == b) || (it.from == b && it.to == a) }.sortedBy { it.at }

    fun lastMessage(a: String, b: String) = conversation(a, b).lastOrNull()

    fun send(from: String, to: String, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        post(from, to, trimmed)
        notify(to, "Сообщение от ${name(from)}", trimmed)
    }

    fun chatPartners(userId: String): List<Person> {
        val partners = if (isCoach(userId)) studentsOf(userId)
        else coaches.map { person(it.id) ?: it } +
            students.filter { it.id != userId && conversation(userId, it.id).isNotEmpty() }.map { person(it.id) ?: it }
        return partners.sortedByDescending { lastMessage(userId, it.id)?.at ?: 0L }
    }

    fun notices(userId: String) = state.notices.filter { it.userId == userId }.sortedByDescending { it.at }

    fun players(userId: String) = students.filter { it.id != userId }.map { person(it.id) ?: it }

    /** Олег скрыл прогресс от других учеников — демо приватности. */
    fun publicRating(studentId: String): Int? = if (studentId == Ids.OLEG) null else rating(studentId)

    fun phonesShared(a: String, b: String) =
        conversation(a, b).any { it.peer?.kind == PeerKind.PHONES && it.peer.status == PeerStatus.ACCEPTED }

    fun hasPendingPeer(kind: PeerKind, a: String, b: String) =
        conversation(a, b).any { it.peer?.kind == kind && it.peer.status == PeerStatus.SENT }

    fun sendPeer(kind: PeerKind, from: String, to: String) {
        if (isCoach(from) || isCoach(to) || hasPendingPeer(kind, from, to)) return
        if (kind == PeerKind.PHONES && phonesShared(from, to)) return
        val text = if (kind == PeerKind.PLAY) "Давай сыграем партию? 🎱" else "Хотите обменяться номерами телефонов?"
        update { it.copy(messages = it.messages + Message(newId(), from, to, text, now(), peer = PeerRequest(kind, PeerStatus.SENT))) }
        notify(to, if (kind == PeerKind.PLAY) "${name(from)} предлагает сыграть" else "${name(from)} предлагает обменяться номерами", text)
    }

    fun answerPeer(messageId: String, userId: String, accept: Boolean) {
        val message = state.messages.firstOrNull { it.id == messageId && it.to == userId } ?: return
        val peer = message.peer?.takeIf { it.status == PeerStatus.SENT } ?: return
        update { s ->
            s.copy(messages = s.messages.map {
                if (it.id == messageId) it.copy(peer = peer.copy(status = if (accept) PeerStatus.ACCEPTED else PeerStatus.DECLINED)) else it
            })
        }
        when {
            accept && peer.kind == PeerKind.PLAY -> {
                post(userId, message.from, "Давай! Когда тебе удобно?")
                notify(message.from, "${name(userId)}: согласие сыграть", "Договоритесь о времени в чате")
            }
            accept -> notify(message.from, "Номера открыты 📞", "${name(userId)}: ${person(userId)?.phone}")
            else -> notify(message.from, "${name(userId)} отказался(ась)", if (peer.kind == PeerKind.PLAY) "Приглашение сыграть" else "Обмен номерами")
        }
    }

    private fun post(from: String, to: String, text: String, bookingId: String? = null) =
        update { it.copy(messages = it.messages + Message(newId(), from, to, text, now(), bookingId)) }

    /** Системные уведомления и напоминания (подключаются в AppState). */
    var notifier: Notifier? = null
    private var seeding = false

    private fun notify(userId: String, title: String, body: String) {
        update { it.copy(notices = it.notices + Notice(newId(), userId, title, body, now())) }
        if (!seeding) notifier?.post(name(userId), title, body)
    }

    // endregion

    // region Групповые тренировки

    fun groupsOf(coachId: String, includePast: Boolean = false) =
        state.groups.filter { it.coachId == coachId && !it.cancelled && (includePast || it.end > now()) }.sortedBy { it.start }

    fun groupsOn(coachId: String, day: LocalDate) =
        state.groups.filter { it.coachId == coachId && !it.cancelled && it.start.toDate() == day }

    fun openGroups(coachId: String, studentId: String) = groupsOf(coachId).filter { canBook(it.venueId, studentId) }

    fun groupsOfStudent(studentId: String) =
        state.groups.filter { !it.cancelled && studentId in it.participants && it.end > now() }.sortedBy { it.start }

    fun group(id: String) = state.groups.firstOrNull { it.id == id }

    fun createGroup(session: GroupSession) {
        if (session.start <= now()) throw DemoError("Выберите время в будущем.")
        val busy = state.bookings.any { it.coachId == session.coachId && it.status.holdsSlot && it.start < session.end && session.start < it.end }
        if (busy) throw DemoError("В это время у вас уже есть запись.")
        update { s ->
            s.copy(
                slots = s.slots.filterNot { it.coachId == session.coachId && it.status == SlotStatus.AVAILABLE && it.start < session.end && session.start < it.end },
                groups = s.groups + session,
            )
        }
        studentsOf(session.coachId).filter { canBook(session.venueId, it.id) }.forEach {
            notify(it.id, "Новая групповая тренировка", "${session.title} · ${Fmt.stamp(session.start)}")
        }
    }

    fun join(groupId: String, studentId: String) {
        val session = group(groupId) ?: throw DemoError("Тренировка не найдена")
        if (studentId in session.participants) return
        if (session.freePlaces == 0) throw DemoError("Мест больше нет.")
        if (!canBook(session.venueId, studentId)) throw DemoError("Это место доступно только по приглашению тренера.")
        update { s -> s.copy(groups = s.groups.map { if (it.id == groupId) it.copy(participants = it.participants + studentId) else it }) }
        post(studentId, session.coachId, "Записался(ась) на групповую: ${session.title}, ${Fmt.stamp(session.start)}")
        notify(session.coachId, "Запись на групповую", "${name(studentId)} · ${session.participants.size + 1}/${session.capacity}")
    }

    fun leave(groupId: String, studentId: String) {
        val session = group(groupId) ?: return
        update { s -> s.copy(groups = s.groups.map { if (it.id == groupId) it.copy(participants = it.participants - studentId) else it }) }
        post(studentId, session.coachId, "Не смогу прийти на групповую ${Fmt.stamp(session.start)}")
    }

    fun cancelGroup(groupId: String) {
        val session = group(groupId) ?: return
        update { s -> s.copy(groups = s.groups.map { if (it.id == groupId) it.copy(cancelled = true) else it }) }
        session.participants.forEach {
            post(session.coachId, it, "Групповая тренировка ${Fmt.stamp(session.start)} отменена")
            notify(it, "Групповая отменена", session.title)
        }
        regenerate(session.coachId)
    }

    // endregion

    // region Новости и магазин

    fun publish(item: News) {
        update { it.copy(news = listOf(item) + it.news) }
        students.forEach { notify(it.id, if (item.tournament) "🏆 ${item.title}" else item.title, "${name(item.authorId)} · Контент") }
    }

    fun deleteNews(id: String) = update { s -> s.copy(news = s.news.filterNot { it.id == id }) }
    fun publish(item: Listing) = update { it.copy(listings = listOf(item) + it.listings) }
    fun deleteListing(id: String) = update { s -> s.copy(listings = s.listings.filterNot { it.id == id }) }

    // endregion

    // region Начальные данные

    fun reset() {
        prefs.edit().remove(KEY).apply()
        seed()
    }

    private fun seed() {
        seeding = true
        try { seedData() } finally { seeding = false }
    }

    private fun seedData() {
        val today = LocalDate.now()
        val flagship = Venue(newId(), Ids.ALEXEY, "Флагман", "Москва, ул. Тверская, 10", setOf(1, 2, 3, 4, 5, 6), listOf(16, 17, 18, 19, 20, 21))
        val tidjon = Venue(newId(), Ids.ALEXEY, "Тиджон", "Москва, Ленинский пр., 45", setOf(7), listOf(12, 13, 14, 15),
            onlySelected = true, allowed = setOf(Ids.IVAN, Ids.NATASHA))
        val pyramid = Venue(newId(), Ids.VERONIKA, "Пирамида", "Москва, ул. Арбат, 25", setOf(1, 3, 5, 7), listOf(10, 11, 12, 13, 14))
        val testHall = Venue(newId(), Ids.ALEXEY, "Тест-зал 24/7", "Для проверки уведомлений", (1..7).toSet(), (0..23).toList(), isTest = true)
        var s = DemoState(venues = listOf(flagship, tidjon, pyramid, testHall))
        s = s.copy(slots = generate(Ids.ALEXEY, s, -45))
        s = s.copy(slots = s.slots + generate(Ids.VERONIKA, s, -45))

        val bookings = mutableListOf<Booking>()
        val slots = s.slots.toMutableList()
        fun seedBooking(coach: String, student: String, dayOffset: Int, status: BookingStatus): Booking? {
            val main = s.venues.first { it.coachId == coach }.id
            val from = today.plusDays(dayOffset.toLong()).at(0)
            val index = slots.indices.filter { slots[it].coachId == coach && slots[it].venueId == main && slots[it].status == SlotStatus.AVAILABLE && slots[it].start >= from }
                .minByOrNull { slots[it].start } ?: return null
            val slot = slots[index]
            slots[index] = slot.copy(status = if (status == BookingStatus.AWAITING) SlotStatus.HELD else SlotStatus.BOOKED)
            val booking = Booking(newId(), slot.id, student, coach, slot.start, 60, coachInfo(coach).price, status, null, slot.start - 3 * 86_400_000L)
            bookings += booking
            return booking
        }
        val evaluations = mutableListOf<Evaluation>()
        val history = listOf(
            -40 to listOf(55, 50, 42, 35, 45),
            -25 to listOf(60, 62, 46, 40, 50),
            -10 to listOf(63, 70, 50, 43, 55),
            -4 to listOf(65, 76, 52, 45, 58),
        )
        for ((offset, values) in history) {
            val b = seedBooking(Ids.ALEXEY, Ids.IVAN, offset, BookingStatus.COMPLETED) ?: continue
            evaluations += Evaluation(b.id, Ids.IVAN, Ids.ALEXEY, Metric.entries.zip(values).associate { it.first.name to it.second },
                "Хороший прогресс в прицеливании, выход пока нестабилен", b.start + 2 * 3_600_000)
        }
        seedBooking(Ids.ALEXEY, Ids.MARIA, -1, BookingStatus.COMPLETED)
        seedBooking(Ids.ALEXEY, Ids.OLEG, 1, BookingStatus.CONFIRMED)
        val ivanNext = seedBooking(Ids.ALEXEY, Ids.IVAN, 1, BookingStatus.CONFIRMED)
        val natashaNext = seedBooking(Ids.ALEXEY, Ids.NATASHA, 1, BookingStatus.CONFIRMED)
        seedBooking(Ids.ALEXEY, Ids.ANNA, 2, BookingStatus.AWAITING)
        seedBooking(Ids.VERONIKA, Ids.ANNA, -2, BookingStatus.COMPLETED)
        seedBooking(Ids.VERONIKA, Ids.OLEG, 2, BookingStatus.AWAITING)
        seedBooking(Ids.VERONIKA, Ids.MARIA, 4, BookingStatus.CONFIRMED)

        val now = now()
        val messages = mutableListOf(
            Message(newId(), Ids.ALEXEY, Ids.IVAN, "Привет! Жду на тренировке, поработаем над выходом на дальний борт 🎱", now - 3 * 3_600_000),
            Message(newId(), Ids.NATASHA, Ids.ALEXEY, "Алексей, добрый день! А можно пораньше? В 18:00 не очень удобно", now - 2 * 3_600_000),
            Message(newId(), Ids.VERONIKA, Ids.IVAN, "Здравствуйте! Если захотите попробовать пул — записывайтесь на утро 🙂", now - 5 * 3_600_000),
        )
        listOfNotNull(ivanNext, natashaNext).forEach {
            messages += Message(newId(), Ids.ALEXEY, it.studentId, "Тренировка подтверждена ✓ Жду вас!", now - 4 * 3_600_000, it.id)
        }

        // Игровая тренировка в ближайшую среду, 20:00, «Флагман».
        val wednesday = today.plusDays(1).with(TemporalAdjusters.nextOrSame(DayOfWeek.WEDNESDAY))
        val group = GroupSession(newId(), Ids.ALEXEY, flagship.id, "Игровая тренировка", wednesday.at(20), 120, 6, 1200,
            listOf(Ids.MARIA, Ids.ANNA))
        val freeSlots = slots.filterNot { it.coachId == Ids.ALEXEY && it.status == SlotStatus.AVAILABLE && it.start < group.end && group.start < it.end }

        val tournament = today.plusDays(14).at(11)
        val news = listOf(
            News(newId(), Ids.ALEXEY, true, "Кубок «Флагмана» — открыта регистрация",
                "Свободная пирамида, сетка на 32 игрока. Взнос 1 500 ₽, призы — кии и медали. Запись у тренера в чате.", tournament, now - 6 * 3_600_000,
                videoUrl = "https://www.youtube.com/results?search_query=русский+бильярд+свободная+пирамида"),
            News(newId(), Ids.VERONIKA, true, "Женский турнир по пулу в «Пирамиде»",
                "Восьмёрка, до 3 побед. Новичкам — отдельная группа.", tournament + 7 * 86_400_000L, now - 26 * 3_600_000),
            News(newId(), Ids.ALEXEY, false, "Итоги осеннего рейтинга", "Иван Петров поднялся на 3-е место клуба. Поздравляем! 🎉", null, now - 3 * 86_400_000L),
        )
        val listings = listOf(
            Listing(newId(), Ids.ALEXEY, MarketCategory.CUES, "Кий «Веста», клён, 160 см", "Б/у полгода, наклейка новая, чехол в подарок", 18_000, now),
            Listing(newId(), Ids.ALEXEY, MarketCategory.CHALK, "Мел Taom V10, 2 шт.", "Новый, в упаковке", 2_400, now),
            Listing(newId(), Ids.VERONIKA, MarketCategory.GLOVES, "Перчатка для пула, размер M", "Для правой и левой руки, есть в наличии", 900, now),
            Listing(newId(), Ids.ALEXEY, MarketCategory.REPAIR, "Замена наклейки и колпачка", "За 1 день, наклейки Kamui и Tiger", 1_500, now),
            Listing(newId(), Ids.VERONIKA, MarketCategory.SERVICE, "Чистка и полировка древка", "Уберу липкость и грязь, восстановлю скольжение", 800, now),
        )
        val notices = (listOf(Ids.IVAN, Ids.NATASHA).map { Notice(newId(), it, "Добро пожаловать в «Биток»", "Выберите тренера и запишитесь во вкладке «Календарь»", now) } +
            coaches.map { Notice(newId(), it.id, "Добро пожаловать в «Биток»", "Новые заявки появятся в «Календаре» и в чате", now) })

        state = DemoState()
        update {
            s.copy(slots = freeSlots, bookings = bookings, evaluations = evaluations, messages = messages, groups = listOf(group),
                news = news, listings = listings, notices = notices)
        }
    }

    // endregion

    companion object {
        private const val KEY = "demoState.v2"
    }
}
