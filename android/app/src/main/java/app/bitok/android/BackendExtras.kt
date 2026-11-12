// Чат (непрочитанные, правка, удаление), уведомления, групповая запись, подписка «Биток Про», видео, подарки.
package app.bitok.android

import android.content.Context
import java.io.File

// region Чат и уведомления

fun DemoBackend.unread(userId: String, partner: String): Int {
    val seen = state.readMarks["$userId|$partner"] ?: 0L
    return conversation(userId, partner).count { it.from == partner && it.at > seen }
}

fun DemoBackend.totalUnread(userId: String) = chatPartners(userId).sumOf { unread(userId, it.id) }

fun DemoBackend.markRead(userId: String, partner: String) {
    if (unread(userId, partner) > 0) update { it.copy(readMarks = it.readMarks + ("$userId|$partner" to now())) }
}

fun DemoBackend.unseenNotices(userId: String): Int {
    val seen = state.noticesSeen[userId] ?: 0L
    return notices(userId).count { it.at > seen }
}

fun DemoBackend.markNoticesSeen(userId: String) = update { it.copy(noticesSeen = it.noticesSeen + (userId to now())) }

fun DemoBackend.editMessage(id: String, userId: String, text: String) {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return
    update { s -> s.copy(messages = s.messages.map { if (it.id == id && it.from == userId) it.copy(text = trimmed, editedAt = now()) else it }) }
}

/** forEveryone — удалить у обоих (только своё сообщение), иначе — только у себя. */
fun DemoBackend.deleteMessage(id: String, userId: String, forEveryone: Boolean) = update { s ->
    val message = s.messages.firstOrNull { it.id == id } ?: return@update s
    if (forEveryone && message.from == userId) s.copy(messages = s.messages - message)
    else s.copy(messages = s.messages.map { if (it.id == id) it.copy(hiddenFor = it.hiddenFor + userId) else it })
}

// endregion

// region Групповая запись, тренеры ученика, подписка

fun DemoBackend.isGroupBooking(id: String) = id in state.groupBookings
fun DemoBackend.markGroup(id: String) = update { it.copy(groupBookings = it.groupBookings + id) }

fun DemoBackend.coachesOf(studentId: String) = coaches.filter { c -> state.bookings.any { it.studentId == studentId && it.coachId == c.id } }

fun DemoBackend.hasSubscription(userId: String) = (state.subscriptions[userId] ?: 0L) > now()

/** Демо-оформление: деньги не списываются. В проде — Google Play Billing. */
fun DemoBackend.subscribe(userId: String, months: Int) {
    val start = maxOf(now(), state.subscriptions[userId] ?: 0L)
    update { it.copy(subscriptions = it.subscriptions + (userId to start + months * 30L * 86_400_000L)) }
    notify(userId, "Биток Про подключён ✨", "Камера-помощник доступна в упражнениях")
}

// endregion

// region Видео

fun videosDir(context: Context) = File(context.filesDir, "videos").apply { mkdirs() }

fun DemoBackend.attachVideo(file: String, exerciseId: String, studentId: String) =
    update { it.copy(videos = it.videos + TrainingVideo(newId(), studentId, exerciseId, file, now())) }

fun DemoBackend.sendVideo(file: String, from: String, to: String, text: String) {
    update { it.copy(messages = it.messages + Message(newId(), from, to, text, now(), videoFile = file)) }
    notify(to, "🎬 Видео от ${name(from)}", text)
}

// endregion

// region Подарки

fun DemoBackend.giftsOf(userId: String) = state.gifts.filter { it.toId == userId }.sortedByDescending { it.at }

fun DemoBackend.setShowInProfile(id: String, value: Boolean) =
    update { s -> s.copy(gifts = s.gifts.map { if (it.id == id) it.copy(showInProfile = value) else it }) }

fun DemoBackend.listing(id: String) = state.listings.firstOrNull { it.id == id }

/** Где забрать подарок: у продавца на ближайшей тренировке получателя, иначе — в его клубе. */
fun DemoBackend.pickupHint(gift: Gift): String {
    val seller = name(gift.sellerId)
    val next = state.bookings.filter { it.studentId == gift.toId && it.coachId == gift.sellerId && it.status.holdsSlot && it.start > now() }
        .minByOrNull { it.start }
    if (next != null) return "Заберите у тренера $seller на тренировке ${Fmt.shortDay(next.start)} в ${Fmt.time(next.start)}, ${place(next.slotId)}."
    val club = venues(gift.sellerId).firstOrNull()?.let { "«${it.name}», ${it.address}" } ?: "клубе"
    return "Заберите у $seller в $club. Напишите продавцу, чтобы договориться о времени."
}

// endregion
