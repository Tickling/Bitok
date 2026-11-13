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
    // Метрики по упражнениям подготовительного уровня
    STANCE("Стойка и мост", "МОСТ"),
    AIMING("Удар в середину", "СЕР"),
    POSITION("Удар в угол", "УГОЛ"),
    CUE_BALL("Сила и возврат битка", "СИЛА"),
    TACTICS("Винт", "ВИНТ"),
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
    /** Тест-зал: слот каждый час, запись за 5 минут до начала — для проверки уведомлений. */
    val isTest: Boolean = false,
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
enum class PeerKind { PLAY, PHONES, FRIEND }

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
    val giftId: String? = null,
    /** Время правки — сообщение помечается «изменено». */
    val editedAt: Long? = null,
    /** У кого сообщение удалено «только у себя». */
    val hiddenFor: List<String> = emptyList(),
    /** Видео выполнения упражнения (файл в files/videos). */
    val videoFile: String? = null,
)

@Serializable
enum class GiftCard(val title: String, val emoji: String, val from: Long, val to: Long) {
    BIRTHDAY("С днём рождения!", "🎂", 0xFFFA739E, 0xFFFDC266),
    VICTORY("За победу!", "🏆", 0xFFF2C74D, 0xFF8C5C0D),
    NEW_YEAR("С Новым годом!", "🎄", 0xFF14734D, 0xFFBF1F2E),
    THANKS("Спасибо!", "🙏", 0xFF4DA3FF, 0xFF6B4DD9),
    JUST_BECAUSE("Просто так", "🎱", 0xFF1F7A45, 0xFF0D331F),
}

/** Подарок: товар из магазина, открытка и поздравление. */
@Serializable
data class Gift(
    val id: String,
    val fromId: String,
    val toId: String,
    val listingId: String,
    val itemTitle: String,
    val sellerId: String,
    val card: GiftCard,
    val message: String,
    val at: Long,
    val opened: Boolean = false,
    /** «Скрыть моё имя»: другие в профиле получателя не видят отправителя. */
    val hideName: Boolean = false,
    val showInProfile: Boolean = true,
    val price: Int? = null,
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
    val imageId: String? = null,
    val videoUrl: String? = null,
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
    val imageId: String? = null,
)

@Serializable
data class Profile(
    val firstName: String,
    val lastName: String,
    val city: String,
    val discipline: String,
    val about: String,
    /** Дата рождения (epoch ms). Другим ученикам по умолчанию не видна; тренер видит всегда. */
    val birthDate: Long? = null,
    /** hidden (по умолчанию), year — только год, dayMonth — только день и месяц. */
    val birthdayVisibility: String = "hidden",
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
    val gifts: List<Gift> = emptyList(),
    val customExercises: List<Exercise> = emptyList(),
    val exerciseResults: List<ExerciseResult> = emptyList(),
    /** «userId|partnerId» → время, когда чат последний раз открывали. */
    val readMarks: Map<String, Long> = emptyMap(),
    val noticesSeen: Map<String, Long> = emptyMap(),
    val groupBookings: Set<String> = emptySet(),
    /** Подписка «Биток Про»: до какого времени действует. */
    val subscriptions: Map<String, Long> = emptyMap(),
    /** «userId|exerciseId» → лучшие звёзды. */
    val stars: Map<String, Int> = emptyMap(),
    val videos: List<TrainingVideo> = emptyList(),
    val chatGroups: List<ChatGroup> = emptyList(),
    val groupMessages: List<GroupMessage> = emptyList(),
    /** Друзья: связь взаимная, хранится у обоих. */
    val friendships: Map<String, Set<String>> = emptyMap(),
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
    NATASHA("Наталья Белова", "+7 900 000-00-04", Role.STUDENT, Ids.NATASHA),
    DMITRY("Дмитрий Орлов (Про)", "+7 900 000-00-05", Role.STUDENT, Ids.DMITRY);

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
    /** Ученик с подпиской «Биток Про». */
    const val DMITRY = "student-dmitry"
}

@Serializable
data class TablePoint(val x: Double, val y: Double)

/** Лузы; SHORT_RAIL — короткий борт напротив битка (возврат, сила удара). */
@Serializable
enum class Pocket(val x: Double, val y: Double) {
    TOP_LEFT(0.0, 0.0), TOP_MIDDLE(80.0, 0.0), TOP_RIGHT(160.0, 0.0),
    BOTTOM_LEFT(0.0, 80.0), BOTTOM_MIDDLE(80.0, 80.0), BOTTOM_RIGHT(160.0, 80.0), SHORT_RAIL(0.0, 40.0)
}

@Serializable
data class Exercise(
    val id: String,
    val number: Int,
    val level: String = "Подготовительный уровень",
    val title: String,
    val details: List<String>,
    val metric: Metric,
    val cueBalls: List<TablePoint>,
    val objectBalls: List<TablePoint> = emptyList(),
    val targets: List<Pocket>,
    val attempts: Int = 10,
    val spin: Boolean = false,
    val rack: Boolean = false,
    val importedBy: String? = null,
) {
    fun target(index: Int): Pocket? = if (targets.isEmpty()) null else targets[minOf(index, targets.size - 1)]

    fun targetPoint(index: Int): TablePoint? {
        val t = target(index) ?: return null
        return if (t == Pocket.SHORT_RAIL && index < cueBalls.size) TablePoint(0.0, cueBalls[index].y) else TablePoint(t.x, t.y)
    }

    val markPoints: List<TablePoint> get() = if (rack) rackPoints(TablePoint(45.0, 40.0)) + cueBalls else cueBalls + objectBalls

    /** Где поставить штатив: за лузой на продолжении линии удара, лицом к ученику. */
    val tripod: Pair<TablePoint, String>
        get() {
            val cue = cueBalls.firstOrNull() ?: TablePoint(80.0, 40.0)
            val t = targetPoint(0) ?: TablePoint(160 - cue.x, if (cue.y < 40) 80.0 else 0.0)
            val dx = t.x - cue.x; val dy = t.y - cue.y
            val len = maxOf(1.0, kotlin.math.hypot(dx, dy))
            val p = TablePoint((t.x + dx / len * 15).coerceIn(-15.0, 175.0), (t.y + dy / len * 15).coerceIn(-15.0, 95.0))
            val side = when {
                t.x <= 0.1 -> "у левого короткого борта, напротив отметки ${t.y.toInt()}"
                t.x >= 159.9 -> "у правого короткого борта, напротив отметки ${t.y.toInt()}"
                t.y <= 0.1 -> "у верхнего длинного борта, напротив отметки ${t.x.toInt()}"
                else -> "у нижнего длинного борта, напротив отметки ${t.x.toInt()}"
            }
            val corner = (t.x <= 0.1 || t.x >= 159.9) && (t.y <= 0.1 || t.y >= 79.9)
            return p to "Штатив: ${if (corner) "за угловой лузой, " else ""}$side, в 50 см от стола, высота 1,6–1,8 м. Камера смотрит на вас вдоль линии удара."
        }

    companion object {
        fun rackPoints(apex: TablePoint): List<TablePoint> {
            val d = 4.6
            return (0 until 5).flatMap { row -> (0..row).map { col -> TablePoint(apex.x - row * d * 0.866, apex.y - row * d / 2 + col * d) } }
        }
    }
}

@Serializable
data class ExerciseResult(
    val id: String,
    val studentId: String,
    val coachId: String,
    val exerciseId: String,
    val made: Int,
    val attempts: Int,
    val at: Long,
) {
    val percent: Int get() = if (attempts == 0) 0 else Math.round(made * 100f / attempts)
}

@Serializable
data class TrainingVideo(val id: String, val studentId: String, val exerciseId: String, val file: String, val at: Long)

@Serializable
data class ChatGroup(val id: String, val title: String, val members: List<String>, val creatorId: String, val at: Long)

/** from == null — системное сообщение («Иван покинул группу»). */
@Serializable
data class GroupMessage(val id: String, val groupId: String, val from: String?, val text: String, val at: Long)
