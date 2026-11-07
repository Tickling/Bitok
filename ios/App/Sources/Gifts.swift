// App/Sources/Gifts.swift — подарки: ученик покупает товар в подарок другому ученику,
// выбирает открытку и пишет поздравление; у получателя — анимация распаковки.
import SwiftUI
import CoreDomain
import DesignSystem

// MARK: - Модель

enum GiftCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case birthday, victory, newYear, thanks, justBecause
    var id: Self { self }

    var title: String {
        switch self {
        case .birthday: "С днём рождения!"
        case .victory: "За победу!"
        case .newYear: "С Новым годом!"
        case .thanks: "Спасибо!"
        case .justBecause: "Просто так"
        }
    }

    var emoji: String {
        switch self {
        case .birthday: "🎂"
        case .victory: "🏆"
        case .newYear: "🎄"
        case .thanks: "🙏"
        case .justBecause: "🎱"
        }
    }

    var colors: [Color] {
        switch self {
        case .birthday: [Color(red: 0.98, green: 0.45, blue: 0.62), Color(red: 0.99, green: 0.76, blue: 0.40)]
        case .victory: [Color(red: 0.95, green: 0.78, blue: 0.30), Color(red: 0.55, green: 0.36, blue: 0.05)]
        case .newYear: [Color(red: 0.08, green: 0.45, blue: 0.30), Color(red: 0.75, green: 0.12, blue: 0.18)]
        case .thanks: [Color(red: 0.30, green: 0.64, blue: 1.0), Color(red: 0.42, green: 0.30, blue: 0.85)]
        case .justBecause: [Color(red: 0.12, green: 0.48, blue: 0.27), Color(red: 0.05, green: 0.20, blue: 0.12)]
        }
    }
}

struct DemoGift: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let fromId: UserID
    let toId: UserID
    let listingId: UUID
    let itemTitle: String
    let priceRubles: Int64?
    let sellerId: UserID
    let card: GiftCard
    let message: String
    var date = Date()
    var opened = false
}

extension DemoBackend {
    /// Неоткрытый подарок пользователя — показывается анимацией при входе.
    func unopenedGift(for userId: UserID) -> DemoGift? {
        gifts.filter { $0.toId == userId && !$0.opened }.sorted { $0.date < $1.date }.first
    }

    func gift(_ id: UUID) -> DemoGift? { gifts.first { $0.id == id } }

    func sendGift(listing: DemoListing, from: UserID, to: UserID, card: GiftCard, message: String) {
        let gift = DemoGift(fromId: from, toId: to, listingId: listing.id, itemTitle: listing.title, priceRubles: listing.priceRubles,
                            sellerId: listing.sellerId, card: card, message: message)
        gifts.append(gift)
        messages.append(DemoMessage(id: UUID(), from: from, to: to, text: "🎁 Подарок: \(listing.title)", date: Date(), giftId: gift.id))
        // Продавцу — заказ: кому передать товар.
        post(from: from, to: listing.sellerId,
             text: "Покупаю «\(listing.title)» в подарок для \(name(to)). Передайте, пожалуйста, на тренировке 🎁", bookingId: nil)
        notify(to, "🎁 Вам подарок от \(name(from))", "\(card.emoji) \(card.title) Откройте приложение, чтобы распаковать")
        notify(listing.sellerId, "Новый заказ-подарок", "\(listing.title) · для \(name(to))")
        save()
    }

    func markOpened(_ id: UUID) {
        guard let index = gifts.firstIndex(where: { $0.id == id }) else { return }
        gifts[index].opened = true
        let gift = gifts[index]
        post(from: gift.toId, to: gift.fromId, text: "Спасибо за подарок! 😍", bookingId: nil)
        notify(gift.fromId, "\(name(gift.toId)) открыл(а) подарок", gift.itemTitle)
        save()
    }
}

// MARK: - Открытка

struct GiftCardView: View {
    let card: GiftCard
    let message: String
    let from: String
    let item: String
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            Text(card.emoji).font(.system(size: compact ? 30 : 56))
            Text(card.title).font(compact ? .headline : .title2.weight(.bold)).fontDesign(.serif)
            if !message.isEmpty {
                Text("«\(message)»").font(compact ? .caption : .body).multilineTextAlignment(.center).lineLimit(compact ? 2 : 6)
            }
            Text("🎁 \(item)").font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold))
            Text("— \(from)").font(compact ? .caption2 : .callout).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(compact ? 12 : 24)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: compact ? 16 : 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 24, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: card.colors[0].opacity(0.45), radius: compact ? 6 : 18, y: 8)
    }
}

// MARK: - Оформление подарка

struct GiftComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let listing: DemoListing
    var onSent: () -> Void = {}
    @State private var recipient: UserID?
    @State private var card: GiftCard = .birthday
    @State private var message = ""

    private var backend: DemoBackend { container.backend }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack {
                        if let photo = MediaStore.shared.image(listing.imageId) {
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                        }
                        VStack(alignment: .leading) {
                            Text(listing.title).font(.headline)
                            Text(listing.priceRubles.map(Fmt.rubles) ?? "Цена договорная").foregroundStyle(palette.textSecondary)
                        }
                    }

                    Text("Кому").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.m) {
                            ForEach(backend.players(for: container.currentUserId)) { player in
                                Button { recipient = player.id } label: {
                                    VStack(spacing: 4) {
                                        Avatar(initials: player.initials, size: 56, userId: player.id)
                                            .overlay(Circle().strokeBorder(recipient == player.id ? palette.accent : .clear, lineWidth: 3))
                                        Text(player.name.split(separator: " ").first.map(String.init) ?? player.name)
                                            .font(.caption.weight(recipient == player.id ? .bold : .regular))
                                            .foregroundStyle(palette.textPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("Открытка").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(GiftCard.allCases) { option in
                                Button { withAnimation(.spring(duration: 0.3)) { card = option } } label: {
                                    VStack(spacing: 4) {
                                        Text(option.emoji).font(.system(size: 30))
                                        Text(option.title).font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                    }
                                    .frame(width: 104, height: 76)
                                    .background(LinearGradient(colors: option.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(card == option ? palette.accent : .clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("Поздравление").font(.headline)
                    TextField("Например: с днём рождения! Пусть каждый удар будет точным 🎱", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(Space.m)
                        .glassCard(cornerRadius: Radius.m)

                    Text("Так увидит получатель").font(.caption).foregroundStyle(palette.textSecondary)
                    GiftCardView(card: card, message: message, from: backend.name(container.currentUserId), item: listing.title)
                }
                .padding(Space.l)
            }
            .safeAreaInset(edge: .bottom) {
                Button(recipient.map { "Подарить · \(backend.name($0).split(separator: " ").first ?? "")" } ?? "Выберите, кому подарить") {
                    guard let recipient else { return }
                    backend.sendGift(listing: listing, from: container.currentUserId, to: recipient, card: card,
                                     message: message.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                    onSent()
                }
                .buttonStyle(.cueGlassProminent)
                .disabled(recipient == nil)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)
            }
            .background(ThemedBackground())
            .navigationTitle("Подарок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }
}

// MARK: - Распаковка у получателя

struct GiftRevealView: View {
    @Environment(\.dismiss) private var dismiss
    let gift: DemoGift
    let fromName: String
    var onClose: () -> Void = {}

    private enum Phase { case closed, opening, opened }
    @State private var phase: Phase = .closed
    @State private var wiggle = false
    @State private var confetti = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [gift.card.colors[0].opacity(0.9), .black], center: .center, startRadius: 40, endRadius: 520)
                .ignoresSafeArea()

            if phase == .opened {
                ConfettiView(colors: gift.card.colors + [.white, .yellow], active: confetti)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 28) {
                Text(phase == .opened ? "Вам подарок!" : "\(fromName) прислал(а) подарок")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                ZStack {
                    if phase == .opened {
                        GiftCardView(card: gift.card, message: gift.message, from: fromName, item: gift.itemTitle)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    } else {
                        giftBox
                    }
                }
                .frame(height: 340)

                if phase == .closed {
                    Text("Нажмите на коробку, чтобы открыть").foregroundStyle(.white.opacity(0.85))
                } else if phase == .opened {
                    Button("Спасибо!") {
                        onClose()
                        dismiss()
                    }
                    .buttonStyle(.cueGlassProminent)
                    .padding(.horizontal, 40)
                }
            }
            .padding()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) { wiggle = true }
        }
    }

    private var giftBox: some View {
        let lidUp = phase == .opening
        return ZStack {
            // Коробка
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: gift.card.colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 170, height: 140)
                .overlay(Rectangle().fill(.white.opacity(0.9)).frame(width: 22))
                .offset(y: 40)
            // Крышка с бантом
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: gift.card.colors.reversed(), startPoint: .top, endPoint: .bottom))
                    .frame(width: 190, height: 44)
                    .overlay(Rectangle().fill(.white.opacity(0.9)).frame(width: 22))
                HStack(spacing: -6) {
                    Ellipse().fill(.white).frame(width: 46, height: 30).rotationEffect(.degrees(-25))
                    Ellipse().fill(.white).frame(width: 46, height: 30).rotationEffect(.degrees(25))
                }
                .offset(y: -30)
            }
            .offset(y: lidUp ? -260 : -50)
            .rotationEffect(.degrees(lidUp ? -35 : 0))
            .opacity(lidUp ? 0 : 1)
        }
        .rotationEffect(.degrees(phase == .closed ? (wiggle ? 4 : -4) : 0))
        .scaleEffect(phase == .opening ? 1.15 : 1)
        .onTapGesture(perform: open)
        .accessibilityLabel("Подарок. Нажмите, чтобы открыть")
        .accessibilityAddTraits(.isButton)
    }

    private func open() {
        guard phase == .closed else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.easeOut(duration: 0.6)) { phase = .opening }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { phase = .opened }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { confetti = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// Конфетти: частицы падают сверху с вращением.
struct ConfettiView: View {
    let colors: [Color]
    let active: Bool

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let duration: Double
        let size: CGFloat
        let spin: Double
        let color: Color
        let drift: CGFloat
    }

    private var pieces: [Piece] {
        (0..<90).map { i in
            var generator = SeededRandom(seed: UInt64(i + 1))
            return Piece(id: i, x: CGFloat.random(in: 0...1, using: &generator),
                         delay: Double.random(in: 0...0.8, using: &generator),
                         duration: Double.random(in: 2.2...3.8, using: &generator),
                         size: CGFloat.random(in: 6...12, using: &generator),
                         spin: Double.random(in: 180...900, using: &generator),
                         color: colors[i % colors.count],
                         drift: CGFloat.random(in: -60...60, using: &generator))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 1.6)
                    .rotationEffect(.degrees(active ? piece.spin : 0))
                    .position(x: piece.x * geometry.size.width + (active ? piece.drift : 0),
                              y: active ? geometry.size.height + 40 : -40)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: active)
            }
        }
    }
}

/// Детерминированный генератор, чтобы конфетти не «прыгало» при перерисовке.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Карточка подарка в чате.
struct GiftMessageCard: View {
    @Environment(\.palette) private var palette
    let gift: DemoGift
    let fromName: String
    let isMine: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GiftCardView(card: gift.card, message: gift.message, from: fromName, item: gift.itemTitle, compact: true)
            if !isMine {
                Button(gift.opened ? "Посмотреть ещё раз" : "Открыть подарок 🎁", action: onOpen).font(.caption.weight(.semibold))
            } else {
                Text(gift.opened ? "Получатель открыл подарок ✓" : "Ждёт, когда откроют").font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: 260)
    }
}
