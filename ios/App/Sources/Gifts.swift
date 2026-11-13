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
    /// «Скрыть моё имя»: в профиле получателя другие не видят отправителя (сам получатель видит).
    var hideName: Bool? = nil
    /// Получатель показывает подарок в своём профиле.
    var showInProfile: Bool? = nil
}

extension DemoBackend {
    /// Неоткрытый подарок пользователя — показывается анимацией при входе.
    func unopenedGift(for userId: UserID) -> DemoGift? {
        gifts.filter { $0.toId == userId && !$0.opened }.sorted { $0.date < $1.date }.first
    }

    func gift(_ id: UUID) -> DemoGift? { gifts.first { $0.id == id } }

    func sendGift(listing: DemoListing, from: UserID, to: UserID, card: GiftCard, message: String, hideName: Bool) {
        let gift = DemoGift(fromId: from, toId: to, listingId: listing.id, itemTitle: listing.title, priceRubles: listing.priceRubles,
                            sellerId: listing.sellerId, card: card, message: message, hideName: hideName, showInProfile: true)
        gifts.append(gift)
        messages.append(DemoMessage(id: UUID(), from: from, to: to, text: "🎁 Подарок: \(listing.title)", date: Date(), giftId: gift.id))
        // Продавцу — заказ: кому передать товар.
        post(from: from, to: listing.sellerId,
             text: "Покупаю «\(listing.title)» в подарок для \(name(to)). Передайте, пожалуйста, на тренировке 🎁", bookingId: nil)
        notify(to, "🎁 Вам подарок от \(name(from))", "\(card.emoji) \(card.title) Откройте приложение, чтобы распаковать")
        notify(listing.sellerId, "Новый заказ-подарок", "\(listing.title) · для \(name(to))")
        save()
    }

    func gifts(of userId: UserID) -> [DemoGift] {
        gifts.filter { $0.toId == userId }.sorted { $0.date > $1.date }
    }

    func setShowInProfile(_ id: UUID, _ value: Bool) {
        guard let index = gifts.firstIndex(where: { $0.id == id }) else { return }
        gifts[index].showInProfile = value
        save()
    }

    func listing(_ id: UUID) -> DemoListing? { listings.first { $0.id == id } }

    /// Где забрать подарок: у продавца на ближайшей тренировке получателя, иначе — в его основном клубе.
    func pickupHint(for gift: DemoGift) -> String {
        let seller = name(gift.sellerId)
        if let next = bookings.filter({ $0.studentId == gift.toId && $0.trainerId == gift.sellerId && $0.status.holdsSlot && $0.startsAt > Date() })
            .min(by: { $0.startsAt < $1.startsAt }) {
            return "Заберите у тренера \(seller) на тренировке \(Fmt.shortDay(next.startsAt)) в \(Fmt.time(next.startsAt)), \(placeTitle(slotId: next.slotId))."
        }
        let club = coach(gift.sellerId).map { "«\($0.clubName)», \($0.clubAddress)" } ?? "клубе"
        return "Заберите у \(seller) в \(club). Напишите продавцу, чтобы договориться о времени."
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

// MARK: - Общие элементы

/// Узор фона в стиле подарков Telegram, но из бильярдных значков.
struct GiftPattern: View {
    var body: some View {
        Canvas { context, size in
            let symbols = ["circle.circle", "star.fill", "sparkle", "trophy", "seal", "circle.grid.cross"]
            var index = 0
            for y in stride(from: 12.0, to: size.height, by: 46) {
                for x in stride(from: (Int(y / 46) % 2 == 0 ? 14.0 : 36.0), to: size.width, by: 44) {
                    let symbol = context.resolve(Image(systemName: symbols[index % symbols.count]))
                    context.opacity = 0.16
                    context.draw(symbol, at: CGPoint(x: x, y: y))
                    index += 1
                }
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }
}

/// Изображение подарка: фото товара или значок на градиенте открытки.
struct GiftArt: View {
    let gift: DemoGift?
    let card: GiftCard
    let imageId: String?
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            if let photo = MediaStore.shared.image(imageId) {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Text("🎱").font(.system(size: size * 0.5))
            }
            Text(card.emoji).font(.system(size: size * 0.22))
                .padding(size * 0.04)
                .background(.white, in: Circle())
                .offset(x: size * 0.38, y: -size * 0.38)
        }
        .frame(width: size, height: size)
        .shadow(color: card.colors[0].opacity(0.5), radius: size * 0.12, y: size * 0.05)
    }
}

// MARK: - Оформление подарка (как в Telegram, в стиле «Битка»)

struct GiftComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let listing: DemoListing
    var onSent: () -> Void = {}
    @State private var recipient: UserID?
    @State private var card: GiftCard = .birthday
    @State private var message = ""
    @State private var hideName = false

    private var backend: DemoBackend { container.backend }
    private var recipientName: String { recipient.map { backend.person($0)?.name.split(separator: " ").first.map(String.init) ?? "" } ?? "…" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    // Карточка подарка на узорном фоне
                    VStack(spacing: Space.m) {
                        Text("Подарок стоимостью \(listing.priceRubles.map(Fmt.rubles) ?? "по договорённости")")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, Space.m).padding(.vertical, 6)
                            .background(.black.opacity(0.18), in: Capsule())
                        VStack(spacing: Space.s) {
                            GiftArt(gift: nil, card: card, imageId: listing.imageId, size: 120)
                            Text("Подарок для \(recipientName)").font(.title3.weight(.bold)).foregroundStyle(.white)
                            Text("\(listing.title)\nМожно показать в профиле. Забрать — у продавца на тренировке.")
                                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(Space.l)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        TextField("Ваше сообщение (необязательно)", text: $message, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(Space.m)
                            .background(.white.opacity(0.85), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .padding(Space.l)
                    .background {
                        ZStack {
                            LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            GiftPattern()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Кому").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.m) {
                                ForEach(backend.players(for: container.currentUserId)) { player in
                                    Button { recipient = player.id } label: {
                                        VStack(spacing: 4) {
                                            Avatar(initials: player.initials, size: 52, userId: player.id)
                                                .overlay(Circle().strokeBorder(recipient == player.id ? palette.accent : .clear, lineWidth: 3))
                                            Text(player.name.split(separator: " ").first.map(String.init) ?? player.name)
                                                .font(.caption.weight(recipient == player.id ? .bold : .regular))
                                                .foregroundStyle(palette.textPrimary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text("Открытка").font(.headline).padding(.top, Space.s)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(GiftCard.allCases) { option in
                                    Button { withAnimation(.spring(duration: 0.3)) { card = option } } label: {
                                        Text(option.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                                            .background(LinearGradient(colors: option.colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
                                            .overlay(Capsule().strokeBorder(card == option ? palette.textPrimary : .clear, lineWidth: 2))
                                            .overlay(alignment: .leading) { Text(option.emoji).offset(x: -6, y: -12) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.s) {
                        Toggle("Скрыть моё имя", isOn: $hideName)
                            .padding(Space.m)
                            .glassCard()
                        Text("Вы можете скрыть имя и сообщение от всех, кто просматривает профиль \(recipientName). Скрытые имя и сообщение увидит только \(recipientName).")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(Space.l)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let recipient else { return }
                    backend.sendGift(listing: listing, from: container.currentUserId, to: recipient, card: card,
                                     message: message.trimmingCharacters(in: .whitespacesAndNewlines), hideName: hideName)
                    dismiss()
                    onSent()
                } label: {
                    Label(recipient == nil ? "Выберите, кому подарить"
                                           : "Отправить подарок за \(listing.priceRubles.map(Fmt.rubles) ?? "договорную цену")",
                          systemImage: "gift.fill")
                }
                .buttonStyle(.cueGlassProminent)
                .disabled(recipient == nil)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)
            }
            .background(ThemedBackground())
            .navigationTitle("Отправить подарок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }
}

// MARK: - Сообщение о подарке в чате

struct GiftMessageCard: View {
    @Environment(\.palette) private var palette
    let gift: DemoGift
    let fromName: String
    let isMine: Bool
    let imageId: String?
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            Text(isMine ? "Вы отправили подарок стоимостью \(gift.priceRubles.map(Fmt.rubles) ?? "—")"
                        : "\(fromName) отправил(а) вам подарок стоимостью \(gift.priceRubles.map(Fmt.rubles) ?? "—")")
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.m).padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
            VStack(spacing: Space.s) {
                GiftArt(gift: gift, card: gift.card, imageId: imageId, size: 92)
                Text(gift.itemTitle).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("\(gift.card.emoji) \(gift.card.title)").font(.caption).foregroundStyle(.white.opacity(0.85))
                Button(action: onOpen) {
                    Text(isMine || gift.opened ? "Посмотреть" : "Открыть")
                        .font(.callout.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                        .background(.white.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(Space.l)
            .frame(width: 240)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
                    GiftPattern()
                    RadialGradient(colors: [gift.card.colors[0].opacity(0.45), .clear], center: .top, startRadius: 4, endRadius: 200)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Подарок: просмотр, «как получить», переход к товару

struct GiftDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let giftId: UUID
    /// Первая распаковка — с анимацией.
    var animated = false
    @State private var revealed = false
    @State private var spin = false
    @State private var burst = false
    @State private var openedListing: DemoListing?

    private var backend: DemoBackend { container.backend }

    var body: some View {
        if let gift = backend.gift(giftId) {
            content(gift)
        }
    }

    private func content(_ gift: DemoGift) -> some View {
        let me = container.currentUserId
        let isRecipient = gift.toId == me
        let listing = backend.listing(gift.listingId)
        return ZStack {
            LinearGradient(colors: gift.card.colors.map { $0.opacity(0.95) } + [.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GiftPattern().ignoresSafeArea()
            // Лучи за подарком
            AngularGradient(colors: [.white.opacity(0.0), .white.opacity(0.35), .white.opacity(0.0), .white.opacity(0.35), .white.opacity(0.0)],
                            center: .center)
                .frame(width: 520, height: 520)
                .mask(Circle().frame(width: 520, height: 520))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .offset(y: -170)
                .opacity(revealed ? 0.55 : 0.9)
                .allowsHitTesting(false)
            if burst {
                ConfettiView(colors: gift.card.colors + [.white, .yellow], active: burst).ignoresSafeArea().allowsHitTesting(false)
            }
            ScrollView {
                VStack(spacing: Space.l) {
                    GiftArt(gift: gift, card: gift.card, imageId: listing?.imageId, size: revealed ? 150 : 190)
                        .scaleEffect(revealed ? 1 : 0.92)
                        .rotation3DEffect(.degrees(revealed ? 0 : 12), axis: (x: 0, y: 1, z: 0))
                        .padding(.top, 60)
                        .onTapGesture(perform: reveal)

                    if revealed {
                        VStack(spacing: Space.s) {
                            Text(isRecipient ? "Подарок для вас" : "Подарок для \(backend.name(gift.toId))")
                                .font(.title2.weight(.bold))
                            Text(gift.itemTitle).font(.headline)
                            Text(senderLine(gift, isRecipient: isRecipient)).font(.callout).opacity(0.9)
                        }
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                        GiftCardView(card: gift.card, message: gift.message, from: senderName(gift, isRecipient: true), item: gift.itemTitle,
                                     compact: true)
                            .transition(.scale.combined(with: .opacity))

                        VStack(alignment: .leading, spacing: Space.s) {
                            Label("Как получить", systemImage: "shippingbox").font(.headline)
                            Text(backend.pickupHint(for: gift)).font(.callout)
                            if let listing {
                                Button {
                                    openedListing = listing
                                } label: {
                                    Label("Перейти к товару", systemImage: "arrow.right.circle.fill")
                                }
                                .font(.callout.weight(.semibold))
                            }
                            if isRecipient {
                                Button {
                                    dismiss()
                                    container.openChat(with: gift.sellerId)
                                } label: {
                                    Label("Написать продавцу", systemImage: "bubble.left")
                                }
                                .font(.callout.weight(.semibold))
                                Toggle("Показывать в профиле", isOn: Binding(get: { gift.showInProfile ?? true },
                                                                             set: { backend.setShowInProfile(gift.id, $0) }))
                                    .font(.callout)
                            }
                        }
                        .padding(Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        Button("Готово") {
                            if isRecipient && !gift.opened { backend.markOpened(gift.id) }
                            dismiss()
                        }
                        .buttonStyle(.cueGlassProminent)
                    } else {
                        Text("\(senderName(gift, isRecipient: isRecipient)) прислал(а) вам подарок")
                            .font(.title3.weight(.bold)).foregroundStyle(.white)
                        Text("Нажмите, чтобы открыть").foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(Space.l)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
            if !animated { revealed = true }
        }
        .sheet(item: $openedListing) { item in ListingDetail(container: container, listing: item) }
    }

    private func senderName(_ gift: DemoGift, isRecipient: Bool) -> String {
        if gift.hideName == true && !isRecipient && gift.fromId != container.currentUserId { return "Тайный отправитель" }
        return backend.name(gift.fromId)
    }

    private func senderLine(_ gift: DemoGift, isRecipient: Bool) -> String {
        var line = "От: \(senderName(gift, isRecipient: isRecipient)) · \(Fmt.shortDay(gift.date))"
        if gift.hideName == true && (isRecipient || gift.fromId == container.currentUserId) {
            line += "\nИмя скрыто от других — его видите только вы"
        }
        return line
    }

    private func reveal() {
        guard !revealed else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { revealed = true }
        burst = false
        DispatchQueue.main.async { burst = true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                Text("«\(message)»").font(compact ? .callout : .body).multilineTextAlignment(.center).lineLimit(6)
            }
            Text("— \(from)").font(compact ? .caption : .callout).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(compact ? 14 : 24)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
}

/// Конфетти: частицы разлетаются сверху с вращением.
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
                         delay: Double.random(in: 0...0.6, using: &generator),
                         duration: Double.random(in: 2.2...3.6, using: &generator),
                         size: CGFloat.random(in: 6...11, using: &generator),
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

/// Подарки в профиле.
struct ProfileGiftsGrid: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let userId: UserID
    @State private var opened: GiftRef?

    var body: some View {
        let isOwner = userId == container.currentUserId
        let gifts = container.backend.gifts(of: userId).filter { isOwner || ($0.showInProfile ?? true) }
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Подарки").font(.headline)
                Text("\(gifts.count)").font(.caption.bold()).foregroundStyle(palette.textSecondary)
            }
            if gifts.isEmpty {
                Text(isOwner ? "Здесь появятся подарки от других игроков" : "Подарков пока нет")
                    .font(.callout).foregroundStyle(palette.textSecondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                    ForEach(gifts) { gift in
                        Button { opened = GiftRef(id: gift.id) } label: {
                            VStack(spacing: 4) {
                                GiftArt(gift: gift, card: gift.card, imageId: container.backend.listing(gift.listingId)?.imageId, size: 72)
                                Text(gift.hideName == true && !isOwner ? "Тайный отправитель" : container.backend.name(gift.fromId))
                                    .font(.caption2).foregroundStyle(palette.textSecondary).lineLimit(1)
                            }
                            .padding(Space.s)
                            .frame(maxWidth: .infinity)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .sheet(item: $opened) { ref in GiftDetailView(container: container, giftId: ref.id) }
    }
}

struct GiftRef: Identifiable, Hashable { let id: UUID }
