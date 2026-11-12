// App/Sources/Birthdays.swift — дата рождения ученика: приватность, поздравление тренеру, скидка на подписку до 14 лет.
import Foundation
import CoreDomain

enum BirthdayVisibility: String, CaseIterable, Identifiable {
    case hidden, year, dayMonth
    var id: Self { self }
    var title: String {
        switch self {
        case .hidden: "Скрыта"
        case .year: "Только год"
        case .dayMonth: "Только день и месяц"
        }
    }
}

extension DemoBackend {
    /// Демо-даты: у Ивана день рождения сегодня (тренер получит уведомление), Наталье 13 лет (подписка за полцены).
    static func seedBirthday(_ id: UserID) -> Date? {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: Date())
        switch id {
        case ivanId: return calendar.date(from: DateComponents(year: 1998, month: today.month, day: today.day))
        case natashaId: return calendar.date(from: DateComponents(year: 2013, month: 3, day: 8))
        case dmitryId: return calendar.date(from: DateComponents(year: 2001, month: 7, day: 21))
        default: return nil
        }
    }

    func birthDate(of id: UserID) -> Date? { profile(for: id).birthDate }

    func age(of id: UserID) -> Int? {
        birthDate(of: id).flatMap { Calendar.current.dateComponents([.year], from: $0, to: Date()).year }
    }

    func isBirthdayToday(_ id: UserID) -> Bool {
        guard let date = birthDate(of: id) else { return false }
        let calendar = Calendar.current
        return calendar.component(.day, from: date) == calendar.component(.day, from: Date())
            && calendar.component(.month, from: date) == calendar.component(.month, from: Date())
    }

    /// Что видят другие ученики (nil — скрыто).
    func publicBirthday(of id: UserID) -> String? {
        let profile = profile(for: id)
        guard let date = profile.birthDate else { return nil }
        switch BirthdayVisibility(rawValue: profile.birthdayVisibility ?? "hidden") ?? .hidden {
        case .hidden: return nil
        case .year: return "Год рождения: \(Calendar.current.component(.year, from: date))"
        case .dayMonth: return "День рождения: " + date.formatted(.dateTime.day().month(.wide).locale(Fmt.locale))
        }
    }

    /// Полная дата для тренера: «12 ноября 1998 · 28 лет».
    func birthdayForCoach(of id: UserID) -> String? {
        guard let date = birthDate(of: id) else { return nil }
        let text = date.formatted(.dateTime.day().month(.wide).year().locale(Fmt.locale))
        return age(of: id).map { "\(text) · \($0) \(Self.yearsWord($0))" } ?? text
    }

    static func yearsWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "год" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "года" }
        return "лет"
    }

    /// Уведомление тренеру о днях рождения его учеников (раз в день на ученика).
    func checkBirthdays(for coachId: UserID) {
        guard isCoach(coachId) else { return }
        let key = "birthdayNotified-\(Calendar.current.component(.year, from: Date()))"
        var done = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        for student in students(of: coachId) where isBirthdayToday(student.id) {
            let mark = "\(coachId)|\(student.id)"
            guard !done.contains(mark) else { continue }
            done.insert(mark)
            notify(coachId, "🎂 Сегодня день рождения: \(name(student.id))",
                   age(of: student.id).map { "Исполняется \($0) \(Self.yearsWord($0)). Поздравьте в чате!" } ?? "Поздравьте в чате!")
            save()
        }
        UserDefaults.standard.set(Array(done), forKey: key)
    }

    /// Скидка 50% на «Биток Про» ученикам младше 14 лет.
    func hasYouthDiscount(_ id: UserID) -> Bool { (age(of: id) ?? 99) < 14 }
}
