// App/Sources/ContentScreens.swift — вкладка «Контент»: новости и турниры, магазин по категориям.
// Тренер публикует новости, товары и услуги; ученик читает и пишет продавцу в чат.
import SwiftUI
import CoreDomain
import DesignSystem

struct ContentRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case news = "Новости", market = "Магазин"
        var id: Self { self }
    }

    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var segment: Segment = .news
    @State private var category: MarketCategory?
    @State private var composingNews = false
    @State private var composingListing = false
    @State private var openedListing: DemoListing?

    private var backend: DemoBackend { container.backend }
    private var isCoach: Bool { container.role == .trainer }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Picker("Раздел", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch segment {
                    case .news: newsList
                    case .market: market
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle("Контент")
            .toolbar {
                if isCoach {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if segment == .news { composingNews = true } else { composingListing = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .accessibilityLabel(segment == .news ? "Опубликовать новость" : "Добавить товар или услугу")
                    }
                }
            }
            .onAppear { if container.uiPage == "market" { segment = .market } }
            .sheet(isPresented: $composingNews) { NewsComposer(container: container) }
            .sheet(isPresented: $composingListing) { ListingComposer(container: container, category: category ?? .cues) }
            .sheet(item: $openedListing) { listing in ListingDetail(container: container, listing: listing) }
        }
    }

    // MARK: Новости

    @ViewBuilder
    private var newsList: some View {
        if backend.news.isEmpty {
            Text("Новостей пока нет").foregroundStyle(palette.textSecondary)
        }
        ForEach(backend.news) { item in
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Label(item.kind.title, systemImage: item.kind == .tournament ? "trophy.fill" : "newspaper")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.kind == .tournament ? palette.accentSecondary : palette.accent)
                    Spacer()
                    Text(Fmt.stamp(item.date)).font(.caption2).foregroundStyle(palette.textSecondary)
                }
                Text(item.title).font(.headline)
                if let eventDate = item.eventDate {
                    Label("\(Fmt.day(eventDate)), \(Fmt.time(eventDate))", systemImage: "calendar")
                        .font(.callout.weight(.semibold))
                }
                if let image = MediaStore.shared.image(item.imageId) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                }
                Text(item.body).font(.callout)
                if let link = item.videoURL, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("Смотреть видео", systemImage: "play.rectangle.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                            .background(palette.accent.opacity(0.14), in: Capsule())
                    }
                }
                HStack {
                    Avatar(initials: backend.person(item.authorId)?.initials ?? "?", size: 22, userId: item.authorId)
                    Text(backend.name(item.authorId)).font(.caption).foregroundStyle(palette.textSecondary)
                    Spacer()
                    if item.authorId == container.currentUserId {
                        Button("Удалить", role: .destructive) { backend.deleteNews(item.id) }.font(.caption)
                    } else if !isCoach && item.kind == .tournament {
                        Button("Записаться у тренера") { container.openChat(with: item.authorId) }.font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    // MARK: Магазин

    @ViewBuilder
    private var market: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                categoryChip(nil, title: "Все", symbol: "square.grid.2x2")
                ForEach(MarketCategory.allCases) { categoryChip($0, title: $0.title, symbol: $0.symbol) }
            }
        }
        let items = backend.listings.filter { category == nil || $0.category == category }
        let goods = items.filter { !$0.category.isService }
        let services = items.filter { $0.category.isService }
        if items.isEmpty {
            Text("В этой категории пока пусто").foregroundStyle(palette.textSecondary)
        }
        if !goods.isEmpty {
            Text("Товары").font(.headline)
            ForEach(goods) { listingRow($0) }
        }
        if !services.isEmpty {
            Text("Услуги: ремонт и обслуживание кия").font(.headline)
            ForEach(services) { listingRow($0) }
        }
    }

    private func categoryChip(_ value: MarketCategory?, title: String, symbol: String) -> some View {
        let selected = category == value
        return Button {
            withAnimation(.spring(duration: 0.25)) { category = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .foregroundStyle(selected ? palette.onAccent : palette.textPrimary)
                .background(selected ? palette.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func listingRow(_ listing: DemoListing) -> some View {
        Button { openedListing = listing } label: {
            HStack(spacing: Space.m) {
                if let photo = MediaStore.shared.image(listing.imageId) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                } else {
                    Image(systemName: listing.category.symbol)
                        .font(.title3)
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 56, height: 56)
                        .background(listing.category.isService ? palette.accentSecondary : palette.accent,
                                    in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.title).font(.callout.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(listing.category.title) · \(backend.name(listing.sellerId))")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text(listing.priceRubles.map { (listing.category.isService ? "от " : "") + Fmt.rubles($0) } ?? "Договорная")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.accent)
            }
            .padding(Space.m)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

/// Карточка товара или услуги.
struct ListingDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let listing: DemoListing

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let photo = MediaStore.shared.image(listing.imageId) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    } else {
                        Image(systemName: listing.category.symbol)
                            .font(.system(size: 44))
                            .foregroundStyle(palette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .background(LinearGradient(colors: [palette.accent, palette.accentSecondary], startPoint: .topLeading,
                                                       endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    }
                    Text(listing.category.title).font(.caption.weight(.semibold)).foregroundStyle(palette.accent)
                    Text(listing.title).font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                    Text(listing.priceRubles.map { (listing.category.isService ? "от " : "") + Fmt.rubles($0) } ?? "Цена договорная")
                        .font(.title3.bold())
                    Text(listing.details).font(.body)
                    HStack {
                        Avatar(initials: container.backend.person(listing.sellerId)?.initials ?? "?", size: 36, userId: listing.sellerId)
                        VStack(alignment: .leading) {
                            Text(listing.category.isService ? "Мастер" : "Продавец").font(.caption).foregroundStyle(palette.textSecondary)
                            Text(container.backend.name(listing.sellerId)).font(.headline)
                        }
                    }
                    if listing.sellerId == container.currentUserId {
                        Button("Снять с публикации", role: .destructive) {
                            container.backend.deleteListing(listing.id)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    } else if container.role == .student {
                        Button("Написать \(listing.category.isService ? "мастеру" : "продавцу")") {
                            container.backend.send(from: container.currentUserId, to: listing.sellerId,
                                                   text: "Здравствуйте! Интересует «\(listing.title)»")
                            dismiss()
                            container.openChat(with: listing.sellerId)
                        }
                        .buttonStyle(.cueGlassProminent)
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}

struct NewsComposer: View {
    @Environment(\.dismiss) private var dismiss
    let container: AppContainer
    @State private var kind: DemoNews.Kind = .tournament
    @State private var title = ""
    @State private var text = ""
    @State private var hasDate = true
    @State private var eventDate = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0,
                                                         of: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()) ?? Date()
    @State private var imageId: String?
    @State private var videoURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $kind) {
                    ForEach(DemoNews.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Section("Публикация") {
                    TextField(kind == .tournament ? "Название турнира" : "Заголовок", text: $title)
                    TextField(kind == .tournament ? "Формат, взнос, призы, как записаться" : "Текст", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    PhotoField(imageId: $imageId)
                    TextField("Ссылка на видео: YouTube, VK, Rutube", text: $videoURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Фото и видео")
                } footer: {
                    if !videoURL.isEmpty && normalizedVideo == nil {
                        Text("Ссылка должна начинаться с https://")
                    }
                }
                Section {
                    Toggle("Указать дату", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Когда", selection: $eventDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, Fmt.locale)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle(kind == .tournament ? "Анонс турнира" : "Новость")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") {
                        container.backend.publish(DemoNews(authorId: container.currentUserId, kind: kind, title: title,
                                                           body: text, eventDate: hasDate ? eventDate : nil,
                                                           imageId: imageId, videoURL: normalizedVideo))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension NewsComposer {
    /// Ссылка на видео: добавляем https://, если его забыли; пустая строка — без видео.
    var normalizedVideo: String? {
        let trimmed = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let link = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let url = URL(string: link), url.host != nil else { return nil }
        return url.absoluteString
    }
}

struct ListingComposer: View {
    @Environment(\.dismiss) private var dismiss
    let container: AppContainer
    @State var category: MarketCategory
    @State private var title = ""
    @State private var details = ""
    @State private var price: Int64?
    @State private var imageId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Категория") {
                    Picker("Категория", selection: $category) {
                        ForEach(MarketCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Фото") {
                    PhotoField(imageId: $imageId)
                }
                Section(category.isService ? "Услуга" : "Товар") {
                    TextField(category.isService ? "Например: замена наклейки" : "Например: кий «Веста», 160 см", text: $title)
                    TextField("Описание, состояние, сроки", text: $details, axis: .vertical).lineLimit(2...6)
                    HStack {
                        Text(category.isService ? "Цена от" : "Цена")
                        Spacer()
                        TextField("договорная", value: $price, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text("₽")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Новое объявление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") {
                        container.backend.publish(DemoListing(sellerId: container.currentUserId, category: category, title: title,
                                                              details: details, priceRubles: price, imageId: imageId))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
