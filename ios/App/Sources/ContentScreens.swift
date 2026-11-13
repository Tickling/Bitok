// App/Sources/ContentScreens.swift — вкладка «Контент»: новости и турниры, магазин по категориям.
// Тренер публикует новости, товары и услуги; ученик читает и пишет продавцу в чат.
import SwiftUI
import PhotosUI
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
    @State private var showPaywall = false

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
                    if container.role == .student && !backend.hasSubscription(container.currentUserId) {
                        ProPromoCard { showPaywall = true }
                    }
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
            .sheet(isPresented: $showPaywall) {
                PaywallView(container: container) { container.selectedTab = .people }
            }
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
    @State private var giftComposer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    let photos = listing.allImageIds.compactMap { MediaStore.shared.image($0) }
                    if !photos.isEmpty {
                        TabView {
                            ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 260)
                                    .clipped()
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                        if photos.count > 1 {
                            Text("\(photos.count) фото — листайте").font(.caption).foregroundStyle(palette.textSecondary)
                        }
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
                    if let specs = listing.specs, !specs.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Характеристики").font(.headline).padding(.bottom, Space.s)
                            ForEach(specs) { spec in
                                HStack(alignment: .top) {
                                    Text(spec.name).foregroundStyle(palette.textSecondary)
                                    Spacer(minLength: Space.m)
                                    Text(spec.value).multilineTextAlignment(.trailing)
                                }
                                .font(.callout)
                                .padding(.vertical, 6)
                                if spec.id != specs.last?.id { Divider() }
                            }
                        }
                        .padding(Space.m)
                        .glassCard()
                    }
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
                        .buttonStyle(.cueSecondary)
                    } else if container.role == .student {
                        if !listing.category.isService {
                            Button {
                                giftComposer = true
                            } label: {
                                Label("Купить в подарок", systemImage: "gift.fill")
                            }
                            .buttonStyle(.cueGlassProminent)
                        }
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
            .sheet(isPresented: $giftComposer) {
                GiftComposer(container: container, listing: listing) {
                    dismiss()
                    if let last = container.backend.gifts.last { container.openChat(with: last.toId) }
                }
            }
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
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State var category: MarketCategory
    @State private var title = ""
    @State private var details = ""
    @State private var priceText = ""
    @State private var imageIds: [String] = []
    @State private var specs: [ListingSpec] = []

    private var price: Int64? { Int64(priceText.filter(\.isNumber)) }

    /// Чего не хватает для публикации.
    private var missing: [String] {
        var result: [String] = []
        if !category.isService && imageIds.isEmpty { result.append("фото") }
        if title.trimmingCharacters(in: .whitespaces).isEmpty { result.append("название") }
        if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("описание") }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $category) {
                        ForEach(MarketCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    } label: { RequiredLabel("Категория") }
                }
                Section {
                    MultiPhotoField(imageIds: $imageIds, limit: 10)
                } header: {
                    RequiredLabel("Фото", required: !category.isService)
                } footer: {
                    Text("До 10 фото. Первое — главное, его видно в списке.")
                }
                Section(category.isService ? "Услуга" : "Товар") {
                    VStack(alignment: .leading, spacing: 2) {
                        RequiredLabel("Название").font(.caption)
                        TextField(category.isService ? "Например: замена наклейки" : "Например: кий «Веста», 160 см", text: $title)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        RequiredLabel("Описание").font(.caption)
                        TextField("Состояние, история, что входит в комплект", text: $details, axis: .vertical).lineLimit(2...6)
                    }
                    HStack {
                        Text(category.isService ? "Цена от" : "Цена")
                        Spacer()
                        TextField("договорная", text: $priceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                            .onChange(of: priceText) { _, value in
                                let formatted = Fmt.groupedDigits(value)
                                if formatted != value { priceText = formatted }
                            }
                        Text("₽")
                    }
                }
                Section {
                    ForEach($specs) { $spec in
                        HStack {
                            TextField("Название", text: $spec.name).frame(maxWidth: 130)
                            Divider()
                            TextField("Значение", text: $spec.value)
                        }
                    }
                    .onDelete { specs.remove(atOffsets: $0) }
                    let unused = category.suggestedSpecs.filter { name in !specs.contains { $0.name == name } }
                    if !unused.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(unused, id: \.self) { name in
                                    Button("+ \(name)") { specs.append(ListingSpec(name: name, value: "")) }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    Button("Своя характеристика", systemImage: "plus") { specs.append(ListingSpec(name: "", value: "")) }
                } header: {
                    Text("Характеристики")
                } footer: {
                    Text("Например: длина, вес, материал — покупатель увидит их таблицей. Смахните влево, чтобы удалить.")
                }
                Section {
                    if missing.isEmpty {
                        Label("Всё заполнено — можно публиковать", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Заполните: " + missing.joined(separator: ", "), systemImage: "exclamationmark.circle")
                            .foregroundStyle(palette.statusCancelled)
                    }
                    Text("* — обязательные поля").font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(ThemedBackground())
            .navigationTitle("Новое объявление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") { publish() }
                        .disabled(!missing.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { hideKeyboard() }
                }
            }
        }
    }

    private func publish() {
        let filled = specs.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        container.backend.publish(DemoListing(sellerId: container.currentUserId, category: category,
                                              title: title.trimmingCharacters(in: .whitespaces),
                                              details: details.trimmingCharacters(in: .whitespacesAndNewlines), priceRubles: price,
                                              imageId: imageIds.first, extraImageIds: Array(imageIds.dropFirst()),
                                              specs: filled.isEmpty ? nil : filled))
        dismiss()
    }
}

/// Подпись поля; обязательное — со звёздочкой.
struct RequiredLabel: View {
    @Environment(\.palette) private var palette
    let title: String
    var required = true
    init(_ title: String, required: Bool = true) { self.title = title; self.required = required }
    var body: some View {
        if required {
            Text(title) + Text(" *").foregroundColor(palette.statusCancelled)
        } else {
            Text(title)
        }
    }
}

/// Несколько фото (до `limit`): лента миниатюр, добавить из галереи, убрать, сделать главным.
struct MultiPhotoField: View {
    @Environment(\.palette) private var palette
    @Binding var imageIds: [String]
    let limit: Int
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !imageIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(Array(imageIds.enumerated()), id: \.element) { index, id in
                            if let image = MediaStore.shared.image(id) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button { imageIds.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").font(.title3)
                                                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(3)
                                        .accessibilityLabel("Убрать фото \(index + 1)")
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        if index == 0 {
                                            Text("Главное").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(.black.opacity(0.6), in: Capsule()).padding(4)
                                        }
                                    }
                                    .onTapGesture {
                                        // Нажатие делает фото главным
                                        guard index > 0 else { return }
                                        imageIds.insert(imageIds.remove(at: index), at: 0)
                                    }
                            }
                        }
                    }
                }
            }
            HStack {
                PhotosPicker(selection: $items, maxSelectionCount: max(1, limit - imageIds.count), matching: .images) {
                    Label("Добавить фото", systemImage: "photo.badge.plus")
                }
                .disabled(imageIds.count >= limit)
                Spacer()
                Text("\(imageIds.count) / \(limit)").font(.caption.monospacedDigit()).foregroundStyle(palette.textSecondary)
            }
            if imageIds.count > 1 {
                Text("Нажмите на фото, чтобы сделать его главным").font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems where imageIds.count < limit {
                    if let data = try? await item.loadTransferable(type: Data.self), let id = MediaStore.shared.save(data) {
                        imageIds.append(id)
                    }
                }
                items = []
            }
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Реклама подписки в «Контенте» для учеников без «Биток Про».
struct ProPromoCard: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Биток Про").font(.headline).foregroundStyle(.white)
                    Text("Камера расставит шары по упражнению, посчитает удары, покажет ошибки на видео и отправит их тренеру")
                        .font(.caption).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.leading)
                    Text("Узнать больше →").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.45, blue: 0.95), Color(red: 0.45, green: 0.18, blue: 0.85)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
