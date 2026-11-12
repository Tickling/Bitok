// Дата рождения ученика: приватность, уведомление тренеру, скидка на подписку до 14 лет.
package app.bitok.android

import java.time.LocalDate
import java.time.Period
import java.time.format.DateTimeFormatter
import java.util.Locale

enum class BirthdayVisibility(val key: String, val title: String) {
    HIDDEN("hidden", "Скрыта"), YEAR("year", "Только год"), DAY_MONTH("dayMonth", "Только день и месяц");
    companion object { fun of(key: String) = entries.firstOrNull { it.key == key } ?: HIDDEN }
}

/** Демо: у Ивана день рождения сегодня, Наталье 13 лет (подписка за полцены). */
fun seedBirthday(id: String): Long? {
    val today = LocalDate.now()
    return when (id) {
        Ids.IVAN -> LocalDate.of(1998, today.monthValue, today.dayOfMonth).at(12)
        Ids.NATASHA -> LocalDate.of(2013, 3, 8).at(12)
        Ids.DMITRY -> LocalDate.of(2001, 7, 21).at(12)
        else -> null
    }
}

fun DemoBackend.birthDate(id: String): LocalDate? = profile(id).birthDate?.toDate()
fun DemoBackend.age(id: String): Int? = birthDate(id)?.let { Period.between(it, LocalDate.now()).years }
fun DemoBackend.isBirthdayToday(id: String): Boolean = birthDate(id)?.let { it.monthValue == LocalDate.now().monthValue && it.dayOfMonth == LocalDate.now().dayOfMonth } ?: false
fun DemoBackend.hasYouthDiscount(id: String) = (age(id) ?: 99) < 14

fun yearsWord(n: Int): String {
    val m10 = n % 10; val m100 = n % 100
    return when { m10 == 1 && m100 != 11 -> "год"; m10 in 2..4 && m100 !in 12..14 -> "года"; else -> "лет" }
}

private val ru = Locale("ru", "RU")

/** Что видят другие ученики (null — скрыто). */
fun DemoBackend.publicBirthday(id: String): String? {
    val date = birthDate(id) ?: return null
    return when (BirthdayVisibility.of(profile(id).birthdayVisibility)) {
        BirthdayVisibility.HIDDEN -> null
        BirthdayVisibility.YEAR -> "Год рождения: ${date.year}"
        BirthdayVisibility.DAY_MONTH -> "День рождения: " + date.format(DateTimeFormatter.ofPattern("d MMMM", ru))
    }
}

fun DemoBackend.birthdayForCoach(id: String): String? {
    val date = birthDate(id) ?: return null
    val age = age(id)
    return date.format(DateTimeFormatter.ofPattern("d MMMM yyyy", ru)) + (age?.let { " · $it ${yearsWord(it)}" } ?: "")
}

/** Уведомление тренеру о днях рождения его учеников (раз в год на ученика). */
fun DemoBackend.checkBirthdays(coachId: String, prefs: android.content.SharedPreferences) {
    if (!isCoach(coachId)) return
    val key = "birthdayNotified-${LocalDate.now().year}"
    val done = prefs.getStringSet(key, emptySet())!!.toMutableSet()
    studentsOf(coachId).filter { isBirthdayToday(it.id) }.forEach { s ->
        val mark = "$coachId|${s.id}"
        if (mark !in done) {
            done += mark
            notify(coachId, "🎂 Сегодня день рождения: ${name(s.id)}", age(s.id)?.let { "Исполняется $it ${yearsWord(it)}. Поздравьте в чате!" } ?: "Поздравьте в чате!")
        }
    }
    prefs.edit().putStringSet(key, done).apply()
}
