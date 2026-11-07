// Модели демо-данных «Битка». Те же сущности и правила, что в iOS (ANALYTICS.md, раздел 5).
package app.bitok.android

import kotlinx.serialization.Serializable

enum class Role { STUDENT, COACH }

@Serializable
enum class BookingStatus(val title: String) {
    AWAITING("Ждёт тренера"),
    CONFIRMED("Подтверждена"),
    COMPLETED("Завершена"),
    REJECTED("Отклонена"),
    CANCELLED_BY_STUDENT("Отменена учеником"),
    CANCELLED_BY_COACH("Отменена тренером"),
    RESCHEDULED("Перенесена"),
    NO_SHOW("Неявка");

    /** Бронь занимает слот: ждёт тренера или подтверждена. */
    val holdsSlot: Boolean get() = this == AWAITING || this == CONFIRMED
}

@Serializable
enum class SlotStatus { AVAILABLE, HELD, BOOKED }

enum class Metric(val title: String, val short: String) {
    STANCE("Стойка и удар", "СТО"),
    AIMING("Прицеливание", "ПРЦ"),
    POSITION("Позиционная игра", "ПОЗ"),
    CUE_BALL("Контроль битка", "БИТ"),
    TACTICS("Тактика", "ТАК"),
}

@Serializable
data class Person(val id: String, val name: String, val phone: String) {
    val initials: String get() = name.split(" ").filter { it.isNotBlank() }.take(2).joinToString("") { it.first().toString() }
    val firstName: String get() = name.substringBefore(" ")
}

@Serializable
data class CoachInfo(
    val rank: String,
    val hours: String,
    val about: String,
    val price: Int,
)

/** Место тренировок со своим расписанием и кругом учеников. weekdays: 1 — Пн … 7 — Вс. */
@Serializable
data class Venue(
    val id: String,
    val coachId: String,
    val name: String,
    val address: String,
    val weekdays: Set<Int>,
    val hours: List<Int>,
    val onlySelected: Boolean = false,
    val allowed: Set<String> = emptySet(),
) {
    val daysTitle: String
        get() = (1..7).filter { it in weekdays }.joinToString(", ") { WEEKDAYS[it - 1] }.ifEmpty { "Дни не выбраны" }
    val hoursTitle: String
        get() = if (hours.isEmpty()) "Время не выбрано" else "%02d:00–%02d:00".format(hours.min(), hours.max() + 1)

    companion object {
        val WEEKDAYS = listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")
    }
}

@Serializable
data class Slot(
    val id: String,
    val coachId: String,
    val venueId: String,
    val table: Int,
    val start: Long,
    val minutes: Int = 60,
    val status: SlotStatus = SlotStatus.AVAILABLE,
) {
    val end: Long get() = start + minutes * 60_000L
}

@Serializable
data class Booking(
    val id: String,
    val slotId: String,
    val studentId: String,
    val coachId: String,
    val start: Long,
    val minutes: Int,
    val price: Int,
    val status: BookingStatus,
    val comment: String? = null,
    val createdAt: Long,
) {
    val end: Long get() = start + minutes * 60_000L
}

@Serializable
data class Evaluation(
    val bookingId: String,
    val studentId: String,
    val coachId: String,
    val scores: Map<String, Int>,
    val comment: String? = null,
    val at: Long,
)

@Serializable
enum class InvitationStatus { SENT, ACCEPTED, DECLINED, OTHER_TIME }

@Serializable
data class Invitation(val slotId: String, val status: InvitationStatus, val comment: String? = null, val bookingId: String? = null)

@Serializable
enum class PeerKind { PLAY, PHONES }

@Serializable
enum class PeerStatus { SENT, ACCEPTED, DECLINED }

@Serializable
data class PeerRequest(val kind: PeerKind, val status: PeerStatus)

@Serializable
data class Message(
    val id: String,
    val from: String,
    val to: String,
    val text: String,
    val at: Long,
    val bookingId: String? = null,
    val invitation: Invitation? = null,
    val peer: PeerRequest? = null,
)

@Serializable
data class GroupSession(
    val id: String,
    val coachId: String,
    val venueId: String,
    val title: String,
    val start: Long,
    val minutes: Int,
    val capacity: Int,
    val price: Int,
    val participants: List<String> = emptyList(),
    val cancelled: Boolean = false,
) {
    val end: Long get() = start + minutes * 60_000L
    val freePlaces: Int get() = (capacity - participants.size).coerceAtLeast(0)
}

@Serializable
data class News(
    val id: String,
    val authorId: String,
    val tournament: Boolean,
    val title: String,
    val body: String,
    val eventAt: Long? = null,
    val at: Long,
)

@Serializable
enum class MarketCategory(val title: String, val isService: Boolean) {
    CUES("Кии", false),
    CHALK("Мелки", false),
    GLOVES("Перчатки", false),
    ACCESSORIES("Аксессуары", false),
    REPAIR("Ремонт кия", true),
    SERVICE("Обслуживание кия", true),
}

@Serializable
data class Listing(
    val id: String,
    val sellerId: String,
    val category: MarketCategory,
    val title: String,
    val details: String,
    val price: Int? = null,
    val at: Long,
)

@Serializable
data class Profile(
    val firstName: String,
    val lastName: String,
    val city: String,
    val discipline: String,
    val about: String,
) {
    val fullName: String get() = listOf(firstName, lastName).filter { it.isNotBlank() }.joinToString(" ")
}

@Serializable
data class Notice(val id: String, val userId: String, val title: String, val body: String, val at: Long)

@Serializable
data class Privacy(
    val showProgress: Boolean = false,
    val showAchievements: Boolean = true,
    val discoverable: Boolean = true,
)

/** Весь «сервер» одним снимком — сохраняется в SharedPreferences как JSON. */
@Serializable
data class DemoState(
    val venues: List<Venue> = emptyList(),
    val slots: List<Slot> = emptyList(),
    val bookings: List<Booking> = emptyList(),
    val evaluations: List<Evaluation> = emptyList(),
    val messages: List<Message> = emptyList(),
    val notices: List<Notice> = emptyList(),
    val groups: List<GroupSession> = emptyList(),
    val news: List<News> = emptyList(),
    val listings: List<Listing> = emptyList(),
    val profiles: Map<String, Profile> = emptyMap(),
    val coachInfo: Map<String, CoachInfo> = emptyMap(),
    /** Ключ «coachId|studentId» → цена в рублях. */
    val studentPrices: Map<String, Int> = emptyMap(),
    val privacy: Privacy = Privacy(),
)

/** Тестовые учётки; код из SMS для всех — 1234. */
enum class DemoAccount(val displayName: String, val phone: String, val role: Role, val userId: String) {
    ALEXEY("Алексей Воронов", "+7 900 000-00-01", Role.COACH, Ids.ALEXEY),
    VERONIKA("Вероника Смирнова", "+7 900 000-00-03", Role.COACH, Ids.VERONIKA),
    IVAN("Иван Петров", "+7 900 000-00-02", Role.STUDENT, Ids.IVAN),
    NATASHA("Наталья Белова", "+7 900 000-00-04", Role.STUDENT, Ids.NATASHA);

    val roleTitle: String get() = if (role == Role.COACH) "Тренер" else "Ученик"

    companion object {
        const val OTP = "1234"
        fun find(phone: String): DemoAccount? {
            val digits = phone.filter { it.isDigit() }.takeLast(10)
            return entries.firstOrNull { it.phone.filter { c -> c.isDigit() }.takeLast(10) == digits }
        }
    }
}

object Ids {
    const val ALEXEY = "coach-alexey"
    const val VERONIKA = "coach-veronika"
    const val IVAN = "student-ivan"
    const val MARIA = "student-maria"
    const val OLEG = "student-oleg"
    const val ANNA = "student-anna"
    const val NATASHA = "student-natasha"
}
