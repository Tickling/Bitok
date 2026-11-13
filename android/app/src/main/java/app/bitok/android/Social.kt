@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Групповые чаты (ученики-друзья + тренер, любой может выйти) и просмотр фото профиля.
package app.bitok.android

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// region Данные

// Друзья: запрос → согласие второй стороны → взаимная дружба.
enum class FriendStatus { NONE, OUTGOING, INCOMING, FRIENDS }

fun DemoBackend.areFriends(a: String, b: String) = state.friendships[a]?.contains(b) == true
fun DemoBackend.friends(userId: String) = (state.friendships[userId] ?: emptySet()).mapNotNull { person(it) }.sortedBy { it.name }

fun DemoBackend.addFriends(a: String, b: String) {
    if (a == b || isCoach(a) || isCoach(b)) return
    update { s -> s.copy(friendships = s.friendships + (a to (s.friendships[a].orEmpty() + b)) + (b to (s.friendships[b].orEmpty() + a))) }
}

/** Удалить из друзей — у обоих, без уведомления. */
fun DemoBackend.removeFriend(a: String, b: String) = update { s ->
    s.copy(friendships = s.friendships + (a to (s.friendships[a].orEmpty() - b)) + (b to (s.friendships[b].orEmpty() - a)))
}

fun DemoBackend.pendingFriendRequest(from: String, to: String) =
    state.messages.lastOrNull { it.from == from && it.to == to && it.peer?.kind == PeerKind.FRIEND && it.peer.status == PeerStatus.SENT }

fun DemoBackend.friendStatus(me: String, other: String) = when {
    areFriends(me, other) -> FriendStatus.FRIENDS
    pendingFriendRequest(me, other) != null -> FriendStatus.OUTGOING
    pendingFriendRequest(other, me) != null -> FriendStatus.INCOMING
    else -> FriendStatus.NONE
}

fun DemoBackend.incomingFriendRequests(userId: String) =
    state.messages.filter { it.to == userId && it.peer?.kind == PeerKind.FRIEND && it.peer.status == PeerStatus.SENT }.sortedByDescending { it.at }

fun DemoBackend.cancelFriendRequest(from: String, to: String) {
    val m = pendingFriendRequest(from, to) ?: return
    update { s -> s.copy(messages = s.messages - m) }
}

fun DemoBackend.chatGroups(userId: String) = state.chatGroups.filter { userId in it.members }
    .sortedByDescending { g -> groupMessages(g.id).lastOrNull()?.at ?: g.at }

fun DemoBackend.chatGroup(id: String) = state.chatGroups.firstOrNull { it.id == id }
fun DemoBackend.groupMessages(id: String) = state.groupMessages.filter { it.groupId == id }.sortedBy { it.at }

fun DemoBackend.createChatGroup(title: String, members: List<String>, creator: String): ChatGroup {
    val group = ChatGroup(newId(), title, listOf(creator) + members.filter { it != creator }, creator, now())
    update { it.copy(chatGroups = it.chatGroups + group, groupMessages = it.groupMessages + GroupMessage(newId(), group.id, null, "${name(creator)} создал(а) группу «$title»", now())) }
    group.members.filter { it != creator }.forEach { notify(it, "Вас добавили в группу «$title»", "Создатель: ${name(creator)}") }
    return group
}

fun DemoBackend.sendToGroup(id: String, from: String, text: String) {
    val group = chatGroup(id) ?: return
    val trimmed = text.trim()
    if (trimmed.isEmpty() || from !in group.members) return
    update { it.copy(groupMessages = it.groupMessages + GroupMessage(newId(), id, from, trimmed, now())) }
    group.members.filter { it != from }.forEach { notify(it, "${group.title}: ${name(from)}", trimmed) }
}

fun DemoBackend.addToGroup(id: String, member: String, by: String) {
    val group = chatGroup(id) ?: return
    if (member in group.members) return
    update { s -> s.copy(chatGroups = s.chatGroups.map { if (it.id == id) it.copy(members = it.members + member) else it },
        groupMessages = s.groupMessages + GroupMessage(newId(), id, null, "${name(by)} добавил(а) ${name(member)}", now())) }
    notify(member, "Вас добавили в группу «${group.title}»", name(by))
}

fun DemoBackend.leaveGroup(id: String, userId: String) = update { s ->
    s.copy(chatGroups = s.chatGroups.mapNotNull { if (it.id == id) it.copy(members = it.members - userId).takeIf { g -> g.members.isNotEmpty() } else it },
        groupMessages = s.groupMessages + GroupMessage(newId(), id, null, "${name(userId)} покинул(а) группу", now()))
}

// endregion

// region Экраны групп

@Composable
fun GroupRow(app: AppState, group: ChatGroup) {
    val p = LocalPalette.current
    val b = app.backend
    val last = b.groupMessages(group.id).lastOrNull()
    GlassCard(onClick = { app.push(Route.GroupChat(group.id)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).background(Brush.linearGradient(listOf(p.accent2, p.accent)), RoundedCornerShape(22.dp)), contentAlignment = Alignment.Center) {
                Text("👥", fontSize = 20.sp)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row {
                    Text(group.title, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, color = p.text)
                    last?.let { Secondary(Fmt.time(it.at)) }
                }
                Secondary(last?.let { (it.from?.let { f -> b.person(f)?.firstName + ": " } ?: "") + it.text } ?: "${group.members.size} участников")
            }
        }
    }
}

@Composable
fun CreateGroupScreen(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    var title by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf(setOf<String>()) }
    Screen("Новая группа", app, bottom = {
        PrimaryButton("Создать", Modifier.padding(16.dp), enabled = title.isNotBlank() && selected.isNotEmpty()) {
            val group = b.createChatGroup(title.trim(), selected.toList(), app.me)
            app.pop(); app.push(Route.GroupChat(group.id))
        }
    }) {
        OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("Название, например «Пятничная пирамида»") }, singleLine = true)
        Title("Друзья")
        val friends = b.friends(app.me)
        if (friends.isEmpty()) Secondary("Пока нет друзей. Предложите ученику сыграть или обменяться номерами в чате — после согласия его можно добавить в группу.", size = 14)
        friends.forEach { f -> PickRow(app, f.id, "Ученик", f.id in selected) { selected = if (f.id in selected) selected - f.id else selected + f.id } }
        Title("Тренер (по желанию)")
        b.coaches.forEach { c -> PickRow(app, c.id, b.coachInfo(c.id).rank, c.id in selected) { selected = if (c.id in selected) selected - c.id else selected + c.id } }
    }
}

@Composable
private fun PickRow(app: AppState, id: String, subtitle: String, checked: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    GlassCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(app.backend.person(id), 34.dp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) { Text(app.backend.name(id), color = p.text); Secondary(subtitle, size = 12) }
            Text(if (checked) "✓" else "", color = p.accent, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        }
    }
}

@Composable
fun GroupChatScreen(app: AppState, groupId: String) {
    val p = LocalPalette.current
    val b = app.backend
    val group = b.chatGroup(groupId)
    val messages = b.groupMessages(groupId)
    val listState = rememberLazyListState()
    var draft by remember { mutableStateOf("") }
    var members by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1) }
    val isMember = group?.members?.contains(app.me) == true
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton({ app.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад", tint = p.accent) }
            Column(Modifier.weight(1f)) {
                Text(group?.title ?: "Группа", fontWeight = FontWeight.SemiBold, color = p.text, fontSize = 18.sp)
                Secondary("${group?.members?.size ?: 0} участников", size = 12)
            }
            TextButton({ members = true }) { Text("👥 Участники") }
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = 12.dp), state = listState, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(messages, key = { it.id }) { m ->
                if (m.from == null) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Text(m.text, color = p.textSecondary, fontSize = 12.sp, modifier = Modifier.background(p.textSecondary.copy(alpha = 0.12f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp))
                    }
                } else {
                    val mine = m.from == app.me
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start, verticalAlignment = Alignment.Bottom) {
                        if (!mine) { Avatar(b.person(m.from), 26.dp); Spacer(Modifier.width(6.dp)) }
                        Column(Modifier.widthIn(max = 280.dp).background(if (mine) p.accent else p.surface, RoundedCornerShape(18.dp)).padding(horizontal = 12.dp, vertical = 8.dp)) {
                            if (!mine) Text(b.name(m.from) + if (b.isCoach(m.from)) " · тренер" else "", color = p.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            Text(m.text, color = if (mine) p.onAccent else p.text)
                            Text(Fmt.time(m.at), fontSize = 11.sp, color = (if (mine) p.onAccent else p.textSecondary).copy(alpha = 0.7f))
                        }
                    }
                }
            }
        }
        if (isMember) Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(draft, { draft = it }, Modifier.weight(1f), placeholder = { Text("Сообщение в группу") }, maxLines = 4, shape = RoundedCornerShape(22.dp))
            IconButton({ b.sendToGroup(groupId, app.me, draft); draft = "" }, enabled = draft.isNotBlank()) { Icon(Icons.AutoMirrored.Filled.Send, "Отправить", tint = p.accent) }
        } else Secondary("Вы покинули группу", Modifier.padding(16.dp))
    }
    if (members && group != null) {
        AlertDialog(
            onDismissRequest = { members = false },
            title = { Text(group.title) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    group.members.forEach { id -> Text((if (id == app.me) "Вы" else b.name(id)) + if (b.isCoach(id)) " · тренер" else "", color = p.text) }
                    val candidates = (b.friends(app.me).map { it.id } + b.coaches.map { it.id }).filter { it !in group.members }
                    if (isMember && candidates.isNotEmpty()) {
                        Secondary("Добавить:")
                        candidates.forEach { id -> TextButton({ b.addToGroup(groupId, id, app.me) }) { Text("+ ${b.name(id)}") } }
                    }
                    if (isMember) TextButton({ confirmLeave = true }) { Text("Покинуть группу", color = p.cancelled) }
                }
            },
            confirmButton = { TextButton({ members = false }) { Text("Готово") } },
        )
    }
    if (confirmLeave) {
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            title = { Text("Покинуть группу «${group?.title}»?") },
            confirmButton = { TextButton({ confirmLeave = false; members = false; b.leaveGroup(groupId, app.me); app.pop() }) { Text("Покинуть", color = p.cancelled) } },
            dismissButton = { TextButton({ confirmLeave = false }) { Text("Отмена") } },
        )
    }
}

// endregion

/** Просмотр фото профиля на весь экран с масштабом. */
@Composable
fun PhotoViewerScreen(app: AppState, userId: String) {
    val context = LocalContext.current
    val bitmap = AvatarStore.get(context, userId)
    var scale by remember { mutableStateOf(1f) }
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTransformGestures { _, _, zoom, _ -> scale = (scale * zoom).coerceIn(1f, 4f) } }) {
        if (bitmap != null) Image(bitmap.asImageBitmap(), null, Modifier.fillMaxSize().graphicsLayer(scaleX = scale, scaleY = scale), contentScale = ContentScale.Fit)
        TextButton({ app.pop() }, Modifier.statusBarsPadding().align(Alignment.TopEnd)) { Text("✕", color = Color.White, fontSize = 24.sp) }
        Text(app.backend.name(userId), color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(24.dp))
    }
}

// region Друзья — экраны

/** Кнопка дружбы в профиле ученика: меняется по состоянию. */
@Composable
fun FriendButton(app: AppState, otherId: String) {
    val p = LocalPalette.current
    val b = app.backend
    var confirm by remember { mutableStateOf(false) }
    when (b.friendStatus(app.me, otherId)) {
        FriendStatus.NONE -> PrimaryButton("👤+ Добавить в друзья") { b.sendPeer(PeerKind.FRIEND, app.me, otherId) }
        FriendStatus.OUTGOING -> SecondaryButton("Запрос отправлен · отменить", Modifier.fillMaxWidth()) { b.cancelFriendRequest(app.me, otherId) }
        FriendStatus.INCOMING -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PrimaryButton("Принять в друзья", Modifier.weight(1f)) { b.pendingFriendRequest(otherId, app.me)?.let { b.answerPeer(it.id, app.me, true) } }
            SecondaryButton("Отклонить", Modifier.weight(1f), p.cancelled) { b.pendingFriendRequest(otherId, app.me)?.let { b.answerPeer(it.id, app.me, false) } }
        }
        FriendStatus.FRIENDS -> SecondaryButton("В друзьях ✓", Modifier.fillMaxWidth()) { confirm = true }
    }
    if (confirm) AlertDialog(
        onDismissRequest = { confirm = false },
        title = { Text("Удалить ${b.name(otherId)} из друзей?") },
        confirmButton = { TextButton({ confirm = false; b.removeFriend(app.me, otherId) }) { Text("Удалить", color = p.cancelled) } },
        dismissButton = { TextButton({ confirm = false }) { Text("Отмена") } },
    )
}

/** Блоки «Запросы в друзья» и «Друзья». */
@Composable
fun FriendsSections(app: AppState) {
    val p = LocalPalette.current
    val b = app.backend
    val requests = b.incomingFriendRequests(app.me)
    if (requests.isNotEmpty()) {
        Text("👤+ Запросы в друзья · ${requests.size}", color = p.accent, fontWeight = FontWeight.Bold, fontSize = 17.sp)
        requests.forEach { r ->
            GlassCard(onClick = { app.push(Route.PersonProfile(r.from)) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(b.person(r.from), 40.dp); Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) { Title(b.name(r.from)); Secondary("хочет добавить вас в друзья") }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton("Принять", Modifier.weight(1f)) { b.answerPeer(r.id, app.me, true) }
                    SecondaryButton("Отклонить", Modifier.weight(1f), p.cancelled) { b.answerPeer(r.id, app.me, false) }
                }
            }
        }
    }
    val friends = b.friends(app.me)
    Title("Друзья · ${friends.size}")
    if (friends.isEmpty()) Secondary("Пока нет друзей")
    friends.forEach { f ->
        GlassCard(onClick = { app.push(Route.PersonProfile(f.id)) }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(f, 40.dp); Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Title(f.name)
                    val coaches = b.coachesOf(f.id).map { it.firstName }
                    Secondary(if (coaches.isEmpty()) "Пока без тренера" else "Тренер: " + coaches.joinToString())
                }
                TextButton({ app.openChat(f.id) }) { Text("💬") }
            }
        }
    }
}

@Composable
fun FriendsScreen(app: AppState) {
    Screen("Друзья", app) {
        FriendsSections(app)
        Secondary("Добавить друга можно в «Чат» → «Ученики» или в профиле ученика. Друзей можно звать в групповые чаты.")
    }
}

// endregion
