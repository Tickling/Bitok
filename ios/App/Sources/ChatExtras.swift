// App/Sources/ChatExtras.swift — непрочитанные чаты, колокольчик уведомлений, правка и удаление сообщений,
// отметка «групповая» у брони, подписка «Биток Про».
import Foundation
import CoreDomain
import BookingDomain

extension DemoBackend {
    // MARK: Непрочитанные

    func unreadCount(for userId: UserID, from partner: UserID) -> Int {
        let seen = readMarks[userId]?[partner] ?? .distantPast
        return conversation(between: userId, and: partner).filter { $0.from == partner && $0.date > seen }.count
    }

    func totalUnread(for userId: UserID) -> Int {
        chatPartners(of: userId).reduce(0) { $0 + unreadCount(for: userId, from: $1.id) }
    }

    func markRead(_ userId: UserID, partner: UserID) {
        guard unreadCount(for: userId, from: partner) > 0 else { return }
        var marks = readMarks[userId] ?? [:]
        marks[partner] = Date()
        readMarks[userId] = marks
        save()
    }

    func unseenNotices(for userId: UserID) -> Int {
        let seen = noticesSeen[userId] ?? .distantPast
        return events(for: userId).filter { $0.date > seen }.count
    }

    func markNoticesSeen(_ userId: UserID) {
        noticesSeen[userId] = Date()
        save()
    }

    // MARK: Правка и удаление

    func editMessage(_ id: UUID, by userId: UserID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = messages.firstIndex(where: { $0.id == id }), messages[index].from == userId else { return }
        messages[index] = DemoMessage(id: messages[index].id, from: messages[index].from, to: messages[index].to, text: trimmed,
                                      date: messages[index].date, bookingId: messages[index].bookingId,
                                      invitation: messages[index].invitation, peerRequest: messages[index].peerRequest,
                                      giftId: messages[index].giftId, editedAt: Date(), hiddenFor: messages[index].hiddenFor)
        save()
    }

    /// `forEveryone` — удалить у обоих (только своё сообщение); иначе — только у себя.
    func deleteMessage(_ id: UUID, by userId: UserID, forEveryone: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if forEveryone && messages[index].from == userId {
            messages.remove(at: index)
        } else {
            messages[index].hiddenFor = (messages[index].hiddenFor ?? []) + [userId]
        }
        save()
    }

    // MARK: Групповая запись

    func isGroupBooking(_ id: BookingID) -> Bool { groupBookings.contains(id) }

    func markGroup(_ id: BookingID) {
        groupBookings.insert(id)
        save()
    }

    // MARK: Подписка «Биток Про»

    func hasSubscription(_ userId: UserID) -> Bool { (subscriptions[userId] ?? .distantPast) > Date() }

    /// Демо-оформление: в проде — StoreKit / ЮKassa, здесь деньги не списываются.
    func subscribe(_ userId: UserID, months: Int) {
        let start = max(Date(), subscriptions[userId] ?? Date())
        subscriptions[userId] = Calendar.current.date(byAdding: .month, value: months, to: start)
        notify(userId, "Биток Про подключён ✨", "Камера-помощник доступна в упражнениях")
        save()
    }

    /// Тренеры, у которых занимается ученик (по записям).
    func coachesOf(_ studentId: UserID) -> [DemoCoach] {
        coaches.filter { coach in bookings.contains { $0.studentId == studentId && $0.trainerId == coach.id } }
    }
}

// MARK: - Видео выполнения упражнений

struct TrainingVideo: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let studentId: UserID
    let exerciseId: String
    let file: String
    var date = Date()
}

extension DemoBackend {
    static var videosFolder: URL { URL.documentsDirectory.appending(path: "videos", directoryHint: .isDirectory) }

    static func videoURL(_ file: String) -> URL { videosFolder.appending(path: file) }

    /// Копирует видео в хранилище приложения и возвращает имя файла.
    func storeVideo(_ url: URL) -> String? {
        try? FileManager.default.createDirectory(at: Self.videosFolder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).mov"
        do {
            try FileManager.default.copyItem(at: url, to: Self.videoURL(name))
            return name
        } catch {
            return nil
        }
    }

    func attachVideo(_ file: String, exercise: Exercise, studentId: UserID) {
        trainingVideos.append(TrainingVideo(studentId: studentId, exerciseId: exercise.id, file: file))
        save()
    }

    func videos(of studentId: UserID, exercise: String) -> [TrainingVideo] {
        trainingVideos.filter { $0.studentId == studentId && $0.exerciseId == exercise }.sorted { $0.date > $1.date }
    }

    func sendVideo(_ file: String, from: UserID, to: UserID, text: String) {
        messages.append(DemoMessage(id: UUID(), from: from, to: to, text: text, date: Date(), videoFile: file))
        notify(to, "🎬 Видео от \(name(from))", text)
        save()
    }

    /// Самостоятельное выполнение: лучшие звёзды и результат в статистике.
    func recordTraining(exercise: Exercise, studentId: UserID, made: Int, attempts: Int, stars: Int) {
        var map = exerciseStars[studentId] ?? [:]
        map[exercise.id] = max(map[exercise.id] ?? 0, stars)
        exerciseStars[studentId] = map
        exerciseResults.append(ExerciseResult(studentId: studentId, coachId: studentId, exerciseId: exercise.id,
                                              made: made, attempts: max(1, attempts)))
        save()
    }

    func stars(of studentId: UserID, exercise: String) -> Int { exerciseStars[studentId]?[exercise] ?? 0 }
}

// MARK: - Слоты «на рассмотрении»

extension DemoBackend {
    /// Слоты, на которые другой ученик уже подал заявку (ждёт тренера): видны как «забронировано», нажать нельзя.
    /// После подтверждения тренером слот становится «booked» и пропадает из расписания совсем.
    func heldSlots(of coachId: UserID, on day: Date, for student: UserID?, now: Date = Date()) -> [BookingSlot] {
        slots.filter { slot in
            slot.trainerId == coachId && Calendar.current.isDate(slot.startsAt, inSameDayAs: day) && slot.startsAt > now
                && !slot.isBookable(at: now)
                && bookings.contains { $0.slotId == slot.id && $0.status == .awaitingCoachApproval && $0.studentId != student }
        }
        .filter { student == nil || canBook(clubId: $0.clubId, student: student!) }
    }
}

// MARK: - Видео-уроки к упражнениям

extension DemoBackend {
    /// Сообщить ученикам тренера, что к упражнению появился видео-урок.
    func announceLesson(exerciseId: String, coachId: UserID) {
        guard let exercise = exercise(exerciseId) else { return }
        for student in students where coachesOf(student.id).contains(where: { $0.id == coachId }) {
            notify(student.id, "🎬 Видео-урок от тренера", "№\(exercise.number) «\(exercise.title)» — как выполнять и на что обратить внимание")
        }
    }
}
