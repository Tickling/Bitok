@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Точка входа и навигация: вход по тестовой учётке → нижние вкладки → экраны поверх вкладок.
package app.bitok.android

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.IconButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = AppState(applicationContext)
        app.applyUiTest(intent)
        // Android 13+: разрешение на уведомления (кроме режима скриншотов).
        if (Build.VERSION.SDK_INT >= 33 && !app.uiTest) {
            registerForActivityResult(ActivityResultContracts.RequestPermission()) {}.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            BitokTheme(app.appearance, app.textSize) {
                ThemedBackground { Root(app) }
            }
        }
    }
}

enum class Tab { CALENDAR, PEOPLE, CHAT, CONTENT, PROFILE }

/** Экраны поверх вкладок (стек «назад»). */
sealed interface Route {
    data class BookingDetail(val id: String) : Route
    data class Chat(val otherId: String) : Route
    data class PersonProfile(val id: String) : Route
    data class StudentDetail(val id: String) : Route
    data class Propose(val studentId: String, val replacing: String? = null) : Route
    data class Confirm(val slotId: String) : Route
    data class Evaluate(val bookingId: String) : Route
    data class Swap(val bookingId: String) : Route
    data class GroupDetail(val id: String) : Route
    data object GroupEditor : Route
    data object Groups : Route
    data object Venues : Route
    data class VenueEditor(val id: String?) : Route
    data object EditProfile : Route
    data class CropAvatar(val uri: String) : Route
    data object AppIcon : Route
    data class GiftComposer(val listingId: String) : Route
    data class GiftDetail(val id: String) : Route
    data class ExerciseDetail(val id: String, val studentId: String) : Route
    data class Exercises(val studentId: String) : Route
    data class StudentStats(val studentId: String) : Route
    data class CameraTrainer(val exerciseId: String, val demo: String? = null) : Route
    data object Customization : Route
    data class Paywall(val exerciseId: String?) : Route
    data object ProWelcome : Route
    data object CoachExercises : Route
    data object Notices : Route
    data class PhotoViewer(val userId: String) : Route
    data object TrainingResult : Route
    data object Progress : Route
    data class GroupChat(val id: String) : Route
    data object CreateGroup : Route
    data object Friends : Route
    data object Settings : Route
    data object Help : Route
    data object Trophies : Route
    data class ListingDetail(val id: String) : Route
    data object NewsComposer : Route
    data object ListingComposer : Route
}

/** Состояние приложения: учётка, вкладка, стек экранов, настройки. */
class AppState(val context: Context) {
    private val prefs = context.getSharedPreferences("bitok", Context.MODE_PRIVATE)
    val backend = DemoBackend(prefs)
    val notifier = Notifier(context).also { backend.notifier = it }

    /** Скриншоты для «Помощи»: CI запускает приложение с параметрами (учётка, вкладка, раздел). */
    var uiTest = false
        private set
    var uiPage by mutableStateOf<String?>(null)
    /** Подарок, который пользователь открыл повторно из чата. */
    var replayGift by mutableStateOf<String?>(null)
    /** Итог самостоятельного выполнения с камерой. */
    var trainingResult by mutableStateOf<TrainingResult?>(null)
    /** Упражнение, которое открыть в камере после оформления подписки. */
    var pendingTrainer: String? = null

    fun applyUiTest(intent: Intent?) {
        val account = intent?.getStringExtra("uiAccount")?.let { runCatching { DemoAccount.valueOf(it) }.getOrNull() } ?: return
        uiTest = true
        notifier.silent = true
        if (intent.getBooleanExtra("uiReset", false)) backend.reset()
        signIn(account)
        tab = runCatching { Tab.valueOf(intent.getStringExtra("uiTab") ?: "CALENDAR") }.getOrDefault(Tab.CALENDAR)
        stack.clear()
        uiPage = intent.getStringExtra("uiPage")
        val chats = mapOf("alexey" to Ids.ALEXEY, "ivan" to Ids.IVAN, "natasha" to Ids.NATASHA, "veronika" to Ids.VERONIKA)
        intent.getStringExtra("uiChat")?.let { chats[it] }?.let { stack.add(Route.Chat(it)) }
        when (uiPage) {
            // Демо-экраны «Биток Про» для карусели в «Помощи»
            "proExercise" -> stack.add(Route.ExerciseDetail("prep-1", account.userId))
            "proPaywall" -> stack.add(Route.Paywall(null))
            "proFraming", "proMarks", "proBalls", "proPerform" -> stack.add(Route.CameraTrainer("prep-3", uiPage!!.removePrefix("pro").lowercase()))
            "proResult" -> {
                trainingResult = demoTrainingResult()
                stack.add(Route.TrainingResult)
            }
            "venues" -> stack.add(Route.Venues)
            "settings" -> stack.add(Route.Settings)
            "help" -> stack.add(Route.Help)
        }
    }

    var account by mutableStateOf(prefs.getString("account", null)?.let { runCatching { DemoAccount.valueOf(it) }.getOrNull() })
        private set
    var tab by mutableStateOf(Tab.CALENDAR)
    val stack = mutableStateListOf<Route>()
    var selectedCoach by mutableStateOf(Ids.ALEXEY)
    var error by mutableStateOf<String?>(null)
    var info by mutableStateOf<String?>(null)

    var appearance by mutableStateOf(runCatching { Appearance.valueOf(prefs.getString("appearance", "AUTO")!!) }.getOrDefault(Appearance.AUTO))
        private set
    var textSize by mutableStateOf(runCatching { TextSize.valueOf(prefs.getString("textSize", "STANDARD")!!) }.getOrDefault(TextSize.STANDARD))
        private set
    var weekGrid by mutableStateOf(prefs.getBoolean("weekGrid", true))
        private set

    val me: String get() = account?.userId ?: Ids.IVAN
    val role: Role get() = account?.role ?: Role.STUDENT
    val isCoach: Boolean get() = role == Role.COACH

    fun signIn(value: DemoAccount) {
        account = value
        prefs.edit().putString("account", value.name).apply()
    }

    fun signOut() {
        account = null
        tab = Tab.CALENDAR
        stack.clear()
        prefs.edit().remove("account").apply()
    }

    fun changeAppearance(value: Appearance) { appearance = value; prefs.edit().putString("appearance", value.name).apply() }
    fun changeTextSize(value: TextSize) { textSize = value; prefs.edit().putString("textSize", value.name).apply() }
    fun changeWeekGrid(value: Boolean) { weekGrid = value; prefs.edit().putBoolean("weekGrid", value).apply() }

    fun push(route: Route) { stack.add(route) }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }

    fun openChat(otherId: String) {
        stack.clear()
        tab = Tab.CHAT
        stack.add(Route.Chat(otherId))
    }

    fun openBooking(coachId: String) {
        stack.clear()
        selectedCoach = coachId
        tab = Tab.CALENDAR
    }

    /** Выполнить действие; ошибку показать в диалоге. */
    fun run(action: () -> Unit) {
        try { action() } catch (e: DemoError) { error = e.message }
    }
}

@Composable
fun Root(app: AppState) {
    if (app.account == null) {
        LoginScreen(app)
        return
    }
    BackHandler(enabled = app.stack.isNotEmpty()) { app.pop() }
    val top = app.stack.lastOrNull()
    if (top != null) {
        RouteScreen(app, top)
    } else {
        Tabs(app)
    }
    // Неоткрытый подарок — сразу красивая распаковка; из чата можно посмотреть ещё раз.
    val gift = app.backend.unopenedGift(app.me)
    if (gift != null && !app.uiTest) {
        androidx.compose.runtime.key(gift.id) { GiftReveal(app, gift) }
    }
    Alerts(app)
}

@Composable
private fun RouteScreen(app: AppState, route: Route) {
    when (route) {
        is Route.BookingDetail -> BookingDetailScreen(app, route.id)
        is Route.Chat -> ChatThreadScreen(app, route.otherId)
        is Route.PersonProfile -> PersonProfileScreen(app, route.id)
        is Route.StudentDetail -> StudentDetailScreen(app, route.id)
        is Route.Propose -> ProposeSlotScreen(app, route.studentId, route.replacing)
        is Route.Confirm -> ConfirmBookingScreen(app, route.slotId)
        is Route.Evaluate -> EvaluateScreen(app, route.bookingId)
        is Route.Swap -> SwapScreen(app, route.bookingId)
        is Route.GroupDetail -> GroupDetailScreen(app, route.id)
        Route.GroupEditor -> GroupEditorScreen(app)
        Route.Groups -> CoachGroupsScreen(app)
        Route.Venues -> VenuesScreen(app)
        is Route.VenueEditor -> VenueEditorScreen(app, route.id)
        Route.EditProfile -> EditProfileScreen(app)
        is Route.CropAvatar -> CropAvatarScreen(app, route.uri)
        Route.AppIcon -> AppIconScreen(app)
        is Route.GiftComposer -> GiftComposerScreen(app, route.listingId)
        is Route.GiftDetail -> GiftDetailScreen(app, route.id)
        is Route.ExerciseDetail -> ExerciseDetailScreen(app, route.id, route.studentId)
        is Route.Exercises -> ExercisesScreen(app, route.studentId)
        is Route.StudentStats -> StudentStatsScreen(app, route.studentId)
        is Route.CameraTrainer -> CameraTrainerScreen(app, route.exerciseId, route.demo)
        Route.Customization -> CustomizationScreen(app)
        is Route.Paywall -> PaywallScreen(app, route.exerciseId)
        Route.ProWelcome -> ProWelcomeScreen(app)
        Route.CoachExercises -> CoachExercisesScreen(app)
        Route.Notices -> NoticesScreen(app)
        is Route.PhotoViewer -> PhotoViewerScreen(app, route.userId)
        Route.TrainingResult -> TrainingResultScreen(app)
        Route.Progress -> ProgressScreen(app)
        is Route.GroupChat -> GroupChatScreen(app, route.id)
        Route.CreateGroup -> CreateGroupScreen(app)
        Route.Friends -> FriendsScreen(app)
        Route.Settings -> SettingsScreen(app)
        Route.Help -> HelpScreen(app)
        Route.Trophies -> TrophiesScreen(app)
        is Route.ListingDetail -> ListingDetailScreen(app, route.id)
        Route.NewsComposer -> NewsComposerScreen(app)
        Route.ListingComposer -> ListingComposerScreen(app)
    }
}

@Composable
private fun Tabs(app: AppState) {
    val p = LocalPalette.current
    val pending = app.backend.pendingRequests(app.me).size + app.backend.totalUnread(app.me)
    androidx.compose.runtime.LaunchedEffect(app.me) {
        app.backend.checkBirthdays(app.me, app.context.getSharedPreferences("bitok", Context.MODE_PRIVATE))
    }
    Scaffold(
        containerColor = Color.Transparent,
        bottomBar = {
            NavigationBar(containerColor = p.backgroundTop) {
                val colors = NavigationBarItemDefaults.colors(selectedIconColor = p.accent, selectedTextColor = p.accent, indicatorColor = p.accent.copy(alpha = 0.14f))
                NavigationBarItem(app.tab == Tab.CALENDAR, { app.tab = Tab.CALENDAR }, { Icon(Icons.Filled.CalendarMonth, null) },
                    label = { Text("Календарь") }, colors = colors)
                if (app.isCoach) NavigationBarItem(app.tab == Tab.PEOPLE, { app.tab = Tab.PEOPLE }, { Icon(Icons.Filled.Group, null) },
                    label = { Text("Ученики") }, colors = colors)
                NavigationBarItem(app.tab == Tab.CHAT, { app.tab = Tab.CHAT }, {
                    BadgedBox(badge = { if (pending > 0) Badge { Text("$pending") } }) { Icon(Icons.AutoMirrored.Filled.Chat, null) }
                }, label = { Text("Чат") }, colors = colors)
                NavigationBarItem(app.tab == Tab.CONTENT, { app.tab = Tab.CONTENT }, { Icon(Icons.Filled.Newspaper, null) },
                    label = { Text("Контент") }, colors = colors)
                NavigationBarItem(app.tab == Tab.PROFILE, { app.tab = Tab.PROFILE }, { Icon(Icons.Filled.AccountCircle, null) },
                    label = { Text("Профиль") }, colors = colors)
            }
        },
    ) { padding ->
        Box(Modifier.padding(bottom = padding.calculateBottomPadding())) {
            when (app.tab) {
                Tab.CALENDAR -> if (app.isCoach) CoachScheduleScreen(app) else StudentBookingScreen(app)
                Tab.PEOPLE -> if (app.isCoach) StudentsScreen(app) else ProgressScreen(app)
                Tab.CHAT -> ChatListScreen(app)
                Tab.CONTENT -> ContentScreen(app)
                Tab.PROFILE -> ProfileScreen(app)
            }
        }
    }
}

@Composable
private fun Alerts(app: AppState) {
    app.error?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { app.error = null },
            confirmButton = { androidx.compose.material3.TextButton({ app.error = null }) { Text("OK") } },
            title = { Text("Не получилось") },
            text = { Text(message) },
        )
    }
    app.info?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { app.info = null },
            confirmButton = { androidx.compose.material3.TextButton({ app.info = null }) { Text("OK") } },
            title = { Text("Готово") },
            text = { Text(message) },
        )
    }
}

/** Общий каркас экрана: заголовок с «назад», прокручиваемое содержимое, нижняя панель. */
@Composable
fun Screen(
    title: String,
    app: AppState?,
    actions: @Composable () -> Unit = {},
    bottom: @Composable () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val p = LocalPalette.current
    // Во вкладках низ занят панелью вкладок — отступ снизу добавляет только экран поверх вкладок.
    val overTabs = app == null || app.stack.isNotEmpty()
    Column(Modifier.fillMaxSize().statusBarsPadding().then(if (overTabs) Modifier.navigationBarsPadding() else Modifier).imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (app != null && app.stack.isNotEmpty()) {
                IconButton({ app.pop() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад", tint = p.accent)
                }
            } else {
                Spacer(Modifier.width(8.dp))
            }
            Text(title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.text, modifier = Modifier.weight(1f),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            actions()
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
        bottom()
    }
}
