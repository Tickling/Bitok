// BookingKit/Sources/BookingUI/BookingStatus+UI.swift
import DesignSystem
import BookingDomain

extension BookingStatus {
    public var pill: StatusPill {
        switch self {
        case .draft: StatusPill(title: "Черновик", systemImage: "square.dashed", color: \.textSecondary)
        case .awaitingCoachApproval: StatusPill(title: "Ждёт тренера", systemImage: "hourglass", color: \.statusPending)
        case .awaitingPayment: StatusPill(title: "Ждёт оплаты", systemImage: "qrcode", color: \.statusPayment)
        case .confirmed: StatusPill(title: "Подтверждена", systemImage: "checkmark.circle", color: \.statusConfirmed)
        case .completed: StatusPill(title: "Завершена", systemImage: "flag.checkered", color: \.statusCompleted)
        case .rejectedByCoach: StatusPill(title: "Отклонена", systemImage: "xmark.circle", color: \.statusCancelled)
        case .cancelledByStudent, .cancelledByCoach: StatusPill(title: "Отменена", systemImage: "xmark.circle", color: \.statusCancelled)
        case .expired: StatusPill(title: "Истекла", systemImage: "clock.badge.xmark", color: \.statusCancelled)
        case .rescheduled: StatusPill(title: "Перенесена", systemImage: "arrow.triangle.2.circlepath", color: \.textSecondary)
        case .noShow: StatusPill(title: "Неявка", systemImage: "person.slash", color: \.statusCancelled)
        case .unknown: StatusPill(title: "Обновите приложение", systemImage: "questionmark.circle", color: \.textSecondary)
        }
    }
}
