@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)

// Чаты, «Игроки клуба», уведомления; диалог с карточками заявок, предложений и запросов между учениками.
package app.bitok.android

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private enum class ChatSegment(val title: String) { CHATS("Чаты"), PLAYERS("Ученики") }

@Composable
fun ChatListScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    var segment by remember { mutableStateOf(if (app.uiPage == "players") ChatSegment.PLAYERS else ChatSegment.CHATS) }
    Screen("Чат", app, actions = {
        // Уведомления — колокольчик с числом новых.
        IconButton({ app.push(Route.Notices) }) {
            BadgedBox(badge = { val n = b.unseenNotices(app.me); if (n > 0) Badge { Text(if (n > 99) "99+" else "$n") } }) {
                Icon(Icons.Filled.Notifications, "Уведомления", tint = p.accent)
            }
        }
    }) {
        if (!app.isCoach) Segmented(ChatSegment.entries, segment, { it.title }) { segment = it }
        when (segment) {
            ChatSegment.CHATS -> {
                // Группы — в «Биток Про»: без подписки ведём на оформление.
                if (!app.isCoach) SecondaryButton(if (b.hasSubscription(app.me)) "👥 Новая группа" else "🔒 Новая группа · Биток Про", Modifier.fillMaxWidth()) {
                    app.push(if (b.hasSubscription(app.me)) Route.CreateGroup else Route.Paywall(null))
                }
                b.chatGroups(app.me).forEach { GroupRow(app, it) }
                b.chatPartners(app.me).forEach { person ->
                val last = b.lastMessage(app.me, person.id)
                GlassCard(onClick = { app.push(Route.Chat(person.id)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(person, 44.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Row {
                                Text(person.name, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, color = p.text)
                                last?.let { Secondary(Fmt.time(it.at)) }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Secondary(last?.text ?: if (b.isCoach(person.id)) "Тренер" else "Ученик", Modifier.weight(1f))
                                // Непрочитанные — синий кружок с числом внутри карточки чата
                                val unread = b.unread(app.me, person.id)
                                if (unread > 0) Text("$unread", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.background(Color(0xFF3380FF), RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 2.dp))
                            }
                        }
                    }
                }
            }
            }
            ChatSegment.PLAYERS -> {
                FriendsSections(app)
                Title("Все ученики")
            }
        }
        if (segment == ChatSegment.PLAYERS) {
            b.players(app.me).filter { !b.areFriends(app.me, it.id) }.forEach { player ->
                GlassCard(onClick = { app.push(Route.PersonProfile(player.id)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(player, 40.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Title(player.name)
                            val coaches = b.coachesOf(player.id).map { it.firstName }
                            Secondary(if (coaches.isEmpty()) "Пока без тренера" else "Тренер: " + coaches.joinToString(), size = 12)
                            Secondary(b.level(b.rating(player.id)), size = 11)
                        }
                        val rating = b.publicRating(player.id)
                        if (rating != null) Text("$rating", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.accent)
                        else Icon(Icons.Filled.Lock, "Игрок скрыл прогресс", tint = p.textSecondary)
                        Icon(Icons.Filled.ChevronRight, null, tint = p.textSecondary)
                    }
                }
            }
        }
    }
}

@Composable
fun NoticesScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    DisposableEffect(Unit) { onDispose { b.markNoticesSeen(app.me) } }
    Screen("Уведомления", app) {
        val notices = b.notices(app.me)
        if (notices.isEmpty()) Secondary("Уведомлений пока нет")
        notices.forEach { n ->
            GlassCard {
                Row {
                    Text(n.title, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, color = p.text)
                    Secondary(Fmt.stamp(n.at), size = 12)
                }
                Secondary(n.body, size = 14)
            }
        }
    }
}

@Composable
fun ChatThreadScreen(app: AppState, otherId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val me = app.me
    val messages = b.conversation(me, otherId)
    val listState = rememberLazyListState()
    var draft by remember { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Message?>(null) }
    var actions by remember { mutableStateOf<Message?>(null) }
    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
        b.markRead(me, otherId)
    }
    actions?.let { message ->
        val mineMessage = message.from == me
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { actions = null },
            title = { Text("Сообщение") },
            text = {
                Column {
                    TextButton({ clipboard.setText(androidx.compose.ui.text.AnnotatedString(message.text)); actions = null }) { Text("Копировать") }
                    if (mineMessage) TextButton({ editing = message; draft = message.text; actions = null }) { Text("Изменить") }
                    TextButton({ b.deleteMessage(message.id, me, false); actions = null }) { Text("Удалить у меня", color = p.cancelled) }
                    if (mineMessage) TextButton({ b.deleteMessage(message.id, me, true); actions = null }) {
                        Text("Удалить у меня и у ${b.person(otherId)?.firstName ?: "собеседника"}", color = p.cancelled)
                    }
                }
            },
            confirmButton = { TextButton({ actions = null }) { Text("Отмена") } },
        )
    }

    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton({ app.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад", tint = p.accent) }
            // Нажатие на собеседника открывает его профиль.
            Row(Modifier.weight(1f).padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp)) { Avatar(b.person(otherId), 36.dp) }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    TextButton({ app.push(Route.PersonProfile(otherId)) }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        Column {
                            Text(b.name(otherId), fontWeight = FontWeight.SemiBold, color = p.text)
                            Secondary(
                                when {
                                    b.isCoach(otherId) -> "Тренер · профиль"
                                    b.phonesShared(me, otherId) -> b.person(otherId)?.phone.orEmpty()
                                    else -> "Ученик · профиль"
                                }, size = 12,
                            )
                        }
                    }
                }
            }
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = 12.dp), state = listState, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(messages, key = { it.id }) { message -> MessageView(app, message, otherId) { actions = it } }
        }
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            when {
                app.isCoach -> IconButton({ app.push(Route.Propose(otherId)) }) { Icon(Icons.Filled.CalendarMonth, "Предложить время", tint = p.accent) }
                b.isCoach(otherId) -> IconButton({ app.openBooking(otherId) }) { Icon(Icons.Filled.CalendarMonth, "Записаться", tint = p.accent) }
                else -> Box {
                    IconButton({ menu = true }) { Icon(Icons.Filled.AddCircleOutline, "Сыграть или обменяться номерами", tint = p.accent) }
                    DropdownMenu(menu, { menu = false }) {
                        if (!b.areFriends(me, otherId)) DropdownMenuItem({ Text("👤+ Добавить в друзья") },
                            enabled = b.friendStatus(me, otherId) == FriendStatus.NONE,
                            onClick = { menu = false; b.sendPeer(PeerKind.FRIEND, me, otherId) })
                        DropdownMenuItem({ Text("🎱 Предложить сыграть") }, enabled = !b.hasPendingPeer(PeerKind.PLAY, me, otherId),
                            onClick = { menu = false; b.sendPeer(PeerKind.PLAY, me, otherId) })
                        if (!b.phonesShared(me, otherId)) {
                            DropdownMenuItem({ Text("📞 Обменяться номерами") }, enabled = !b.hasPendingPeer(PeerKind.PHONES, me, otherId),
                                onClick = { menu = false; b.sendPeer(PeerKind.PHONES, me, otherId) })
                        }
                    }
                }
            }
            OutlinedTextField(draft, { draft = it }, Modifier.weight(1f), placeholder = { Text(if (editing == null) "Сообщение" else "Изменить сообщение") }, maxLines = 4,
                shape = RoundedCornerShape(22.dp))
            IconButton({
                val e = editing
                if (e != null) { b.editMessage(e.id, me, draft); editing = null } else b.send(me, otherId, draft)
                draft = ""
            }, enabled = draft.isNotBlank()) {
                Icon(Icons.AutoMirrored.Filled.Send, "Отправить", tint = p.accent)
            }
        }
    }
}

@Composable
private fun MessageView(app: AppState, message: Message, otherId: String, onLongPress: (Message) -> Unit) {
    val p = LocalPalette.current
    val b = app.backend
    val mine = message.from == app.me
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        val booking = message.bookingId?.let { b.booking(it) }
        val gift = message.giftId?.let { b.gift(it) }
        when {
            message.videoFile != null -> Column(horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
                VideoBox(app.context, message.videoFile, Modifier.width(230.dp).height(300.dp))
                Text(message.text, color = p.text, fontSize = 14.sp, modifier = Modifier.widthIn(max = 260.dp))
                Secondary(Fmt.time(message.at), size = 11)
            }
            gift != null -> GiftMessage(app, gift, mine)
            message.peer != null -> PeerCard(app, message, message.peer, otherId)
            message.invitation != null -> InvitationCard(app, message, message.invitation)
            booking != null -> BookingCard(app, message, booking)
            else -> Column(
                Modifier.widthIn(max = 280.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(if (mine) p.accent else p.surface, RoundedCornerShape(18.dp))
                    // Долгое нажатие: копировать, изменить своё, удалить
                    .combinedClickable(onClick = {}, onLongClick = { onLongPress(message) })
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                Text(message.text, color = if (mine) p.onAccent else p.text)
                Text((if (message.editedAt != null) "изменено · " else "") + Fmt.time(message.at), fontSize = 11.sp, color = (if (mine) p.onAccent else p.textSecondary).copy(alpha = 0.7f),
                    modifier = Modifier.align(Alignment.End))
            }
        }
    }
}

@Composable
private fun BookingCard(app: AppState, message: Message, booking: Booking) {
    val p = LocalPalette.current
    val b = app.backend
    GlassCard(Modifier.widthIn(max = 310.dp), onClick = { app.push(Route.BookingDetail(booking.id)) }) {
        Text(message.text, fontWeight = FontWeight.SemiBold, color = p.text)
        Text("📅 ${Fmt.shortDay(booking.start)} · ${Fmt.range(booking.start, booking.minutes)}", color = p.text, fontSize = 14.sp)
        Secondary("📍 ${b.place(booking.slotId)}")
        StatusPill(booking.status)
        if (booking.status == BookingStatus.AWAITING) {
            if (app.isCoach) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SecondaryButton("Отклонить", color = p.cancelled) { app.run { b.reject(booking.id) } }
                    PrimaryButton("Подтвердить", Modifier.weight(1f)) { app.run { b.approve(booking.id) } }
                }
                SecondaryButton("Предложить другое время", Modifier.fillMaxWidth()) { app.push(Route.Propose(booking.studentId, booking.id)) }
            } else {
                Secondary("⏳ Ожидает подтверждения тренера")
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Подробнее", color = p.accent, fontSize = 13.sp, modifier = Modifier.weight(1f))
            if (app.isCoach && b.swapCandidates(booking.id).isNotEmpty()) {
                TextButton({ app.push(Route.Swap(booking.id)) }) { Text("⇄ Поменять", fontSize = 13.sp) }
            }
            if (!app.isCoach && booking.status.holdsSlot) {
                TextButton({ app.run { b.cancel(booking.id, app.me) } }) { Text("Отменить", color = p.cancelled, fontSize = 13.sp) }
            }
        }
        Secondary(Fmt.time(message.at), size = 11)
    }
}

@Composable
private fun InvitationCard(app: AppState, message: Message, invitation: Invitation) {
    val p = LocalPalette.current
    val b = app.backend
    val slot = b.slot(invitation.slotId) ?: return
    GlassCard(Modifier.widthIn(max = 310.dp)) {
        Text("📅 Предложение тренировки", fontWeight = FontWeight.SemiBold, color = p.text)
        Text(Fmt.day(slot.start), color = p.text)
        Secondary("${Fmt.range(slot.start, slot.minutes)} · ${b.place(slot.id)}")
        invitation.comment?.let { Text("«$it»", fontSize = 13.sp, color = p.text) }
        when (invitation.status) {
            InvitationStatus.SENT -> if (app.isCoach) Secondary("⏳ Ждём ответа ученика") else {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    PrimaryButton("Принять", Modifier.weight(1f)) { app.run { b.answerInvitation(message.id, app.me, InvitationAnswer.ACCEPT) } }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SecondaryButton("Другое время") {
                        app.run { b.answerInvitation(message.id, app.me, InvitationAnswer.OTHER_TIME); app.openBooking(message.from) }
                    }
                    SecondaryButton("Нет", color = p.cancelled) { app.run { b.answerInvitation(message.id, app.me, InvitationAnswer.DECLINE) } }
                }
            }
            InvitationStatus.ACCEPTED -> Text("✓ Принято — тренировка в календаре", color = p.completed, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            InvitationStatus.DECLINED -> Text("Отклонено", color = p.cancelled, fontSize = 13.sp)
            InvitationStatus.OTHER_TIME -> Secondary("Ученик выбирает другое время")
        }
        Secondary(Fmt.time(message.at), size = 11)
    }
}

@Composable
private fun PeerCard(app: AppState, message: Message, request: PeerRequest, otherId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val mine = message.from == app.me
    val play = request.kind == PeerKind.PLAY
    val friend = request.kind == PeerKind.FRIEND
    val uri = LocalUriHandler.current
    GlassCard(Modifier.widthIn(max = 310.dp)) {
        Text(if (friend) "👤+ Запрос в друзья" else if (play) "🎱 Приглашение сыграть" else "📞 Обмен номерами", fontWeight = FontWeight.SemiBold, color = p.text)
        Text(message.text, color = p.text)
        when (request.status) {
            PeerStatus.SENT -> if (mine) Secondary("⏳ Ждём ответа") else Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PrimaryButton(if (friend) "Принять" else if (play) "Сыграем!" else "Да, обменяться", Modifier.weight(1f)) { b.answerPeer(message.id, app.me, true) }
                SecondaryButton("Нет", color = p.cancelled) { b.answerPeer(message.id, app.me, false) }
            }
            PeerStatus.ACCEPTED -> if (friend) {
                Text("✓ Теперь вы друзья 🤝", color = p.completed, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            } else if (play) {
                Text("✓ Договорились сыграть", color = p.completed, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                if (!b.phonesShared(app.me, otherId) && !b.hasPendingPeer(PeerKind.PHONES, app.me, otherId)) {
                    SecondaryButton("Обменяться номерами") { b.sendPeer(PeerKind.PHONES, app.me, otherId) }
                }
            } else {
                Text("✓ Номера открыты", color = p.completed, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                listOf(message.from, message.to).forEach { id ->
                    val person = b.person(id) ?: return@forEach
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(if (id == app.me) "Вы" else person.name, Modifier.weight(1f), fontSize = 13.sp, color = p.text)
                        TextButton({ uri.openUri("tel:" + person.phone.filter { it.isDigit() || it == '+' }) }) { Text("📞 ${person.phone}", fontSize = 13.sp) }
                    }
                }
            }
            PeerStatus.DECLINED -> Text("Отклонено", color = p.cancelled, fontSize = 13.sp)
        }
        Secondary(Fmt.time(message.at), size = 11)
    }
}

/** Профиль собеседника: тренер, ученик (для тренера) или игрок клуба (для ученика). */
@Composable
fun PersonProfileScreen(app: AppState, personId: String) {
    val b = app.backend
    if (app.isCoach && !b.isCoach(personId)) return StudentDetailScreen(app, personId)
    val p = LocalPalette.current
    val person = b.person(personId)
    val uri = LocalUriHandler.current
    Screen(if (b.isCoach(personId)) "Тренер" else "Игрок", app) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Avatar(person, 96.dp)
            Text(person?.name ?: "", fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        }
        if (b.isCoach(personId)) {
            val info = b.coachInfo(personId)
            Secondary(info.rank, Modifier.align(Alignment.CenterHorizontally), 16)
            GlassCard {
                b.venues(personId).filter { app.isCoach || b.canBook(it.id, app.me) }.forEach { Text("📍 ${it.name}, ${it.address}", color = p.text) }
                Text("🕒 ${info.hours}", color = p.text)
                if (info.about.isNotBlank()) Text("💬 ${info.about}", color = p.text)
                if (b.bookingsOfStudent(app.me).any { it.coachId == personId }) {
                    TextButton({ uri.openUri("tel:" + person?.phone?.filter { it.isDigit() || it == '+' }) }) { Text("📞 ${person?.phone}") }
                }
            }
            if (!app.isCoach) PrimaryButton("Записаться к тренеру") { app.openBooking(personId) }
            SecondaryButton("Написать", Modifier.fillMaxWidth()) { app.openChat(personId) }
        } else {
            val rating = b.publicRating(personId)
            Secondary(b.level(b.rating(personId)), Modifier.align(Alignment.CenterHorizontally), 16)
            if (rating != null) {
                GlassCard {
                    Row { Title("Прогресс", Modifier.weight(1f)); Text("$rating", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.accent) }
                    val progress = b.progress(personId)
                    Metric.entries.forEach { MetricBar(it.title, progress[it] ?: 0) }
                }
            } else {
                GlassCard { Text("🔒 Игрок скрыл прогресс от других учеников", color = p.textSecondary) }
            }
            if (b.phonesShared(app.me, personId)) {
                TextButton({ uri.openUri("tel:" + person?.phone?.filter { it.isDigit() || it == '+' }) }) { Text("📞 ${person?.phone}") }
            } else {
                Secondary("Телефон откроется, если вы обменяетесь номерами в чате")
            }
            if (!app.isCoach && personId != app.me) FriendButton(app, personId)
            b.publicBirthday(personId)?.let { Secondary("🎂 $it", size = 14) }
            ProfileGifts(app, personId)
            if (false) {
            }
            PrimaryButton("Написать") { app.openChat(personId) }
        }
    }
}
