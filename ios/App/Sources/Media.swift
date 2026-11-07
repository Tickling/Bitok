// App/Sources/Media.swift — уведомления, фото (товары, новости), редактор аватарки, выбор значка приложения.
import SwiftUI
import PhotosUI
import UserNotifications
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI

// MARK: - Уведомления

/// Системные уведомления демо-режима: события (заявка, подтверждение, сообщение) и напоминания о тренировке.
@MainActor
final class LocalNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotifier()
    static let enabledKey = "notifications.enabled"
    static let reminderKey = "reminder.minutes"

    /// Скриншоты в CI: уведомления и запрос разрешения выключены.
    var isUITest: Bool { UserDefaults.standard.string(forKey: "uiAccount") != nil }

    private var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAccess() async {
        guard !isUITest else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func post(to recipient: String, title: String, body: String) {
        guard enabled, !isUITest else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Для: \(recipient)"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Напоминание ученику за N минут до тренировки (N — в «Настройках»).
    func scheduleReminder(for booking: Booking, studentName: String) {
        guard enabled, !isUITest else { return }
        let minutes = UserDefaults.standard.object(forKey: Self.reminderKey) as? Int ?? 120
        Task { try? await LocalReminderScheduler().schedule(for: booking, minutesBefore: minutes) }
    }

    func cancelReminder(for bookingId: BookingID) {
        Task { await LocalReminderScheduler().cancel(for: bookingId) }
    }

    /// Показывать баннер, даже когда приложение открыто.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

// MARK: - Фото товаров и новостей

/// Хранилище картинок на устройстве: Documents/media/<id>.jpg. В проде — Media Service + CDN.
@MainActor
@Observable
final class MediaStore {
    static let shared = MediaStore()
    @ObservationIgnored private var cache: [String: UIImage] = [:]
    private var version = 0

    private var folder: URL { URL.documentsDirectory.appending(path: "media", directoryHint: .isDirectory) }

    func image(_ id: String?) -> UIImage? {
        _ = version
        guard let id else { return nil }
        if let cached = cache[id] { return cached }
        let image = UIImage(contentsOfFile: folder.appending(path: "\(id).jpg").path)
        cache[id] = image
        return image
    }

    /// Сохраняет уменьшенную до 1280 px копию и возвращает её id.
    func save(_ data: Data) -> String? {
        guard let original = UIImage(data: data) else { return nil }
        let scale = min(1, 1280 / max(original.size.width, original.size.height))
        let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
        let id = UUID().uuidString
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? resized.jpegData(compressionQuality: 0.85)?.write(to: folder.appending(path: "\(id).jpg"))
        cache[id] = resized
        version += 1
        return id
    }
}

/// Поле «Фото»: выбрать из галереи, посмотреть, удалить.
struct PhotoField: View {
    @Environment(\.palette) private var palette
    @Binding var imageId: String?
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let image = MediaStore.shared.image(imageId) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            }
            HStack {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(imageId == nil ? "Добавить фото" : "Заменить фото", systemImage: "photo.badge.plus")
                }
                if imageId != nil {
                    Spacer()
                    Button("Убрать", role: .destructive) { imageId = nil }
                }
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    imageId = MediaStore.shared.save(data)
                }
                item = nil
            }
        }
    }
}

// MARK: - Редактор аватарки

/// Перемещение и масштаб фото внутри круга; снизу — как оно будет выглядеть в разных местах приложения.
struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let image: UIImage
    let onDone: (UIImage) -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let side: CGFloat = 300

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                ZStack {
                    cropped(size: side, clip: false)
                    // Затемнение вне круга
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .mask {
                            Rectangle().overlay(Circle().blendMode(.destinationOut)).compositingGroup()
                        }
                        .allowsHitTesting(false)
                    Circle().strokeBorder(.white, lineWidth: 2).allowsHitTesting(false)
                }
                .frame(width: side, height: side)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in clamp() }
                        .simultaneously(with:
                            MagnifyGesture()
                                .onChanged { value in scale = min(5, max(1, lastScale * value.magnification)) }
                                .onEnded { _ in clamp() }
                        )
                )

                Text("Перетащите фото и разведите пальцы, чтобы приблизить")
                    .font(.callout).foregroundStyle(palette.textSecondary)

                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: Binding(get: { scale }, set: { scale = $0; clamp() }), in: 1...5)
                    Image(systemName: "plus.magnifyingglass")
                }
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.l)

                VStack(spacing: Space.s) {
                    Text("Так будет видно в приложении").font(.caption).foregroundStyle(palette.textSecondary)
                    HStack(alignment: .bottom, spacing: Space.l) {
                        preview(96, "Профиль")
                        preview(56, "Карточка")
                        preview(40, "Список")
                        preview(28, "Чат")
                    }
                }
                Spacer()
            }
            .padding(.top, Space.l)
            .frame(maxWidth: .infinity)
            .background(ThemedBackground())
            .navigationTitle("Фото профиля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let renderer = ImageRenderer(content: cropped(size: 512, clip: true))
                        renderer.scale = 1
                        if let result = renderer.uiImage { onDone(result) }
                        dismiss()
                    }
                }
            }
        }
    }

    /// Фото с текущими масштабом и сдвигом в квадрате `size` (сдвиг пропорционален размеру).
    private func cropped(size: CGFloat, clip: Bool) -> some View {
        let factor = size / side
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .offset(x: offset.width * factor, y: offset.height * factor)
            .frame(width: size, height: size)
            .clipped()
    }

    private func preview(_ size: CGFloat, _ title: String) -> some View {
        VStack(spacing: 4) {
            cropped(size: size, clip: true).clipShape(Circle())
            Text(title).font(.caption2).foregroundStyle(palette.textSecondary)
        }
    }

    /// Фото не должно уезжать так, чтобы в круге было пусто.
    private func clamp() {
        let limit = (side * scale - side) / 2
        offset = CGSize(width: min(limit, max(-limit, offset.width)), height: min(limit, max(-limit, offset.height)))
        lastOffset = offset
        lastScale = scale
    }
}

// MARK: - Значок приложения

struct AppIconOption: Identifiable {
    let id: String          // имя ассета-превью и суффикс значка
    let title: String
    let subtitle: String

    /// nil — основной значок.
    var iconName: String? { id == "Classic" ? nil : "AppIcon-\(id)" }

    static let all: [AppIconOption] = [
        AppIconOption(id: "Classic", title: "Стеклянный биток", subtitle: "Текущий значок"),
        AppIconOption(id: "Oxblood", title: "Слоновая кость", subtitle: "Шар на бордо с золотым кантом"),
        AppIconOption(id: "Midnight", title: "Мел", subtitle: "Синий мел на ночном фоне"),
        AppIconOption(id: "Eight", title: "Восьмёрка", subtitle: "Чёрный шар №8"),
        AppIconOption(id: "Felt", title: "Сукно", subtitle: "Стол сверху, удар в лузу"),
        AppIconOption(id: "Line", title: "Минимализм", subtitle: "Кий и шар"),
        AppIconOption(id: "Neon", title: "Неон", subtitle: "Светящийся контур, как в баре"),
        AppIconOption(id: "Gold", title: "Золото", subtitle: "Чемпионский шар"),
        AppIconOption(id: "Pyramid", title: "Пирамида", subtitle: "Треугольник шаров"),
        AppIconOption(id: "Cues", title: "Скрещённые кии", subtitle: "Два кия и шар на сукне"),
        AppIconOption(id: "Rising", title: "Растущая пирамида", subtitle: "Шары как график роста"),
    ]
}

struct AppIconPicker: View {
    @Environment(\.palette) private var palette
    @State private var current = UIApplication.shared.alternateIconName
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                ForEach(AppIconOption.all) { option in
                    let selected = current == option.iconName
                    Button { apply(option) } label: {
                        VStack(spacing: Space.s) {
                            Image("IconPreview-\(option.id)")
                                .resizable()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(selected ? palette.accent : .clear, lineWidth: 3))
                            Text(option.title).font(.callout.weight(.semibold)).foregroundStyle(palette.textPrimary)
                            Text(option.subtitle).font(.caption).foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                            if selected {
                                Label("Выбран", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.l)
            Text("iOS покажет короткое сообщение о смене значка — это нормально.")
                .font(.caption).foregroundStyle(palette.textSecondary).padding(.horizontal, Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Значок приложения")
        .errorAlert($errorText)
    }

    private func apply(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorText = "Это устройство не поддерживает смену значка"
            return
        }
        UIApplication.shared.setAlternateIconName(option.iconName) { error in
            Task { @MainActor in
                if let error { errorText = error.localizedDescription } else { current = option.iconName }
            }
        }
    }
}
