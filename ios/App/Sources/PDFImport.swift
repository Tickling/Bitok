// App/Sources/PDFImport.swift — тренер загружает PDF с упражнениями: текст берётся из PDF,
// а если это скан — распознаётся на устройстве (Vision, русский язык). Из текста извлекаются номер,
// название, координаты битка и шаров («Биток 70:40», «по линии 60»), луза, винт — и строится схема.
// Тренер проверяет результат и при необходимости правит схему вручную.
import SwiftUI
import PDFKit
import Vision
import UniformTypeIdentifiers
import PhotosUI
import AVKit
import CoreDomain
import DesignSystem
import ProgressDomain

enum PDFExerciseImporter {
    struct Line { let text: String; let x: CGFloat; let y: CGFloat }

    /// Возвращает распознанные упражнения и сырой текст (для проверки тренером).
    static func extract(from url: URL, coachId: UserID) async -> (exercises: [Exercise], text: String) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { return ([], "") }
        var lines: [Line] = []
        let plain = document.string ?? ""
        if plain.filter(\.isLetter).count > 60 {
            lines = plain.split(whereSeparator: \.isNewline).enumerated()
                .map { Line(text: String($0.element), x: 0, y: CGFloat($0.offset)) }
        } else {
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) { lines += await ocr(page: page, pageIndex: index) }
            }
        }
        let level = lines.first { $0.text.lowercased().contains("уровень") }?.text.trimmingCharacters(in: .whitespaces)
        let exercises = parse(lines: lines, level: level ?? "Из PDF", coachId: coachId)
        return (exercises, lines.map(\.text).joined(separator: "\n"))
    }

    /// Распознавание скана: страница рендерится крупно и режется на плитки, чтобы мелкий текст читался.
    private static func ocr(page: PDFPage, pageIndex: Int) async -> [Line] {
        let bounds = page.bounds(for: .mediaBox)
        let targetLong: CGFloat = 9000
        let scale = min(8, targetLong / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let tile: CGFloat = 1800, overlap: CGFloat = 200
        var result: [Line] = []
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let rect = CGRect(x: x, y: y, width: min(tile, size.width - x), height: min(tile, size.height - y))
                if let image = render(page: page, bounds: bounds, scale: scale, rect: rect) {
                    let found = await recognize(image)
                    for item in found {
                        // Переводим координаты плитки в координаты всей страницы (сверху вниз).
                        let px = rect.minX + item.box.minX * rect.width
                        let py = rect.minY + (1 - item.box.maxY) * rect.height
                        result.append(Line(text: item.text, x: px / size.width, y: CGFloat(pageIndex) + py / size.height))
                    }
                }
                x += tile - overlap
            }
            y += tile - overlap
        }
        // Убираем дубли с перекрытий плиток.
        var unique: [Line] = []
        for line in result where !unique.contains(where: { $0.text == line.text && abs($0.x - line.x) < 0.01 && abs($0.y - line.y) < 0.01 }) {
            unique.append(line)
        }
        return unique
    }

    private static func render(page: PDFPage, bounds: CGRect, scale: CGFloat, rect: CGRect) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            let cg = context.cgContext
            cg.translateBy(x: -rect.minX, y: bounds.height * scale - rect.minY)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cg)
        }
        return image.cgImage
    }

    private static func recognize(_ image: CGImage) async -> [(text: String, box: CGRect)] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let items = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
                }
                continuation.resume(returning: items)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ru-RU", "en-US"]
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: Разбор текста

    static func parse(lines: [Line], level: String, coachId: UserID) -> [Exercise] {
        let headerPattern = /[Уу]пражнени[ея]\s*[№N#]?\s*(\d+)/
        let headers = lines.compactMap { line -> (Line, Int)? in
            guard let match = line.text.firstMatch(of: headerPattern), let number = Int(match.1) else { return nil }
            return (line, number)
        }
        guard !headers.isEmpty else { return [] }
        // Строки относятся к ближайшему заголовку выше в той же колонке.
        var blocks: [Int: [Line]] = [:]
        for line in lines where !headers.contains(where: { $0.0.text == line.text && $0.0.y == line.y }) {
            let candidates = headers.filter { header in
                line.y > header.0.y && abs(line.x - header.0.x) < 0.06 && line.y - header.0.y < 0.35
            }
            guard let owner = candidates.min(by: { (line.y - $0.0.y) < (line.y - $1.0.y) }) else { continue }
            blocks[owner.1, default: []].append(line)
        }
        return headers.map { header, number in
            let body = (blocks[number] ?? []).sorted { $0.y < $1.y }.map(\.text)
            return exercise(number: number, lines: body, level: level, coachId: coachId)
        }
        .sorted { $0.number < $1.number }
    }

    static func exercise(number: Int, lines: [String], level: String, coachId: UserID) -> Exercise {
        let title = lines.first ?? "Упражнение №\(number)"
        let all = lines.joined(separator: " ").lowercased()
        func pairs(_ prefix: String) -> [TablePoint] {
            let pattern = try? NSRegularExpression(pattern: prefix + #"\s*(\d{1,3})\s*[:;.,]\s*(\d{1,3})"#, options: [.caseInsensitive])
            let ns = all as NSString
            return pattern?.matches(in: all, range: NSRange(location: 0, length: ns.length)).compactMap { match in
                guard let x = Double(ns.substring(with: match.range(at: 1))), let y = Double(ns.substring(with: match.range(at: 2))),
                      x <= 160, y <= 80 else { return nil }
                return TablePoint(x: x, y: y)
            } ?? []
        }
        var cue = pairs("биток")
        let objects = pairs("шар")
        if cue.isEmpty {
            // «Биток по линии 60» — линия по длинному борту, биток на середине ширины стола.
            let pattern = try? NSRegularExpression(pattern: #"лини[ия]\s*(\d{1,3})"#)
            let ns = all as NSString
            cue = pattern?.matches(in: all, range: NSRange(location: 0, length: ns.length)).compactMap {
                Double(ns.substring(with: $0.range(at: 1))).map { TablePoint(x: min($0, 155), y: 45) }
            } ?? []
        }
        if cue.isEmpty { cue = [TablePoint(x: 70, y: 40)] }
        let target: Pocket = all.contains("середин") && !all.contains("через середину") ? .topMiddle
            : (all.contains("возврат") || all.contains("силой") || all.contains("борт")) && !all.contains("угол") ? .shortRail : .topLeft
        let metric: MetricKey = all.contains("винт") && !all.contains("винт 0") ? .tacticalThinking
            : all.contains("мост") || all.contains("стойк") || all.contains("машинк") ? .stanceAndStroke
            : all.contains("сил") || all.contains("возврат") ? .cueBallControl
            : target == .topMiddle ? .aiming : .positionPlay
        let attempts = (try? NSRegularExpression(pattern: #"(\d{1,2})\s*удар"#))
            .flatMap { $0.firstMatch(in: all, range: NSRange(location: 0, length: (all as NSString).length)) }
            .flatMap { Int((all as NSString).substring(with: $0.range(at: 1))) } ?? 10
        return Exercise(id: "pdf-\(UUID().uuidString.prefix(8))-\(number)", number: number, level: level, title: title,
                        details: Array(lines.dropFirst()), metric: metric, cueBalls: cue, objectBalls: objects,
                        targets: [target], attempts: max(1, attempts), spin: metric == .tacticalThinking,
                        rack: all.contains("пирамид"), importedBy: coachId)
    }
}

// MARK: - Экраны тренера

struct CoachExercisesView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var importing = false
    @State private var processing = false
    @State private var review: ImportReview?
    @State private var editing: Exercise?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Label("Загрузите PDF с упражнениями", systemImage: "doc.richtext").font(.headline)
                    Text("Приложение найдёт упражнения, координаты шаров («Биток 70:40», «по линии 60»), лузу и винт и построит схему: где клеить точки и что делать. Перед сохранением вы проверите и поправите результат.")
                        .font(.callout).foregroundStyle(palette.textSecondary)
                    HStack {
                        Button {
                            importing = true
                        } label: {
                            Label(processing ? "Распознаю…" : "Выбрать PDF", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.cueGlassProminent)
                        .disabled(processing)
                        if processing { ProgressView() }
                    }
                    Button {
                        editing = Exercise(id: "custom-\(UUID().uuidString.prefix(8))", number: container.backend.allExercises.count + 1,
                                           level: "Мои упражнения", title: "", details: [], metric: .aiming,
                                           cueBalls: [TablePoint(x: 70, y: 40)], targets: [.topMiddle], importedBy: container.currentUserId)
                    } label: {
                        Label("Добавить вручную", systemImage: "plus")
                    }
                }
                .padding(Space.m)
                .glassCard()

                let groups = Dictionary(grouping: container.backend.allExercises, by: \.level)
                ForEach(groups.keys.sorted(), id: \.self) { level in
                    Text(level).font(.headline).padding(.top, Space.s)
                    ForEach(groups[level]?.sorted { $0.number < $1.number } ?? []) { exercise in
                        NavigationLink {
                            ExerciseDetailView(container: container, exercise: exercise, studentId: container.currentUserId)
                        } label: {
                            ExerciseRow(exercise: exercise, level: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Упражнения и уроки")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            processing = true
            Task {
                let found = await PDFExerciseImporter.extract(from: url, coachId: container.currentUserId)
                processing = false
                review = ImportReview(exercises: found.exercises, text: found.text)
            }
        }
        .sheet(item: $review) { item in ImportReviewView(container: container, review: item) }
        .sheet(item: $editing) { item in ExerciseEditor(exercise: item, container: container) { container.backend.saveImported([$0]) } }
    }
}

struct ImportReview: Identifiable {
    let id = UUID()
    var exercises: [Exercise]
    let text: String
}

/// Проверка распознанного: схема каждого упражнения, можно убрать или поправить.
struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State var review: ImportReview
    @State private var editing: Exercise?
    @State private var showText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if review.exercises.isEmpty {
                        ContentUnavailableView("Упражнения не найдены", systemImage: "doc.text.magnifyingglass",
                                               description: Text("Текст в файле слишком мелкий или нечёткий. Загрузите файл лучшего качества или добавьте упражнения вручную."))
                    } else {
                        Text("Найдено упражнений: \(review.exercises.count). Проверьте схемы — точки можно передвинуть.")
                            .font(.callout).foregroundStyle(palette.textSecondary)
                    }
                    ForEach(review.exercises) { exercise in
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack {
                                Text("№\(exercise.number) · \(exercise.metric.title)").font(.caption).foregroundStyle(palette.textSecondary)
                                Spacer()
                                Button("Править") { editing = exercise }.font(.caption.weight(.semibold))
                                Button(role: .destructive) { review.exercises.removeAll { $0.id == exercise.id } } label: {
                                    Image(systemName: "trash")
                                }
                                .font(.caption)
                            }
                            Text(exercise.title).font(.headline)
                            TableSchemeView(exercise: exercise).clipShape(RoundedRectangle(cornerRadius: Radius.s))
                            ForEach(exercise.details, id: \.self) { Text($0).font(.caption) }
                        }
                        .padding(Space.m)
                        .glassCard()
                    }
                    if !review.text.isEmpty {
                        DisclosureGroup("Распознанный текст", isExpanded: $showText) {
                            Text(review.text).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        .padding(Space.m)
                        .glassCard()
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle("Импорт из PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        container.backend.saveImported(review.exercises)
                        dismiss()
                    }
                    .disabled(review.exercises.isEmpty)
                }
            }
            .sheet(item: $editing) { item in
                ExerciseEditor(exercise: item) { updated in
                    if let index = review.exercises.firstIndex(where: { $0.id == updated.id }) { review.exercises[index] = updated }
                }
            }
        }
    }
}

/// Что ставит нажатие на стол в редакторе.
enum SchemePlaceMode: String, CaseIterable {
    case cue, object
    var title: String { self == .cue ? "Биток" : "Прицельный шар" }
}

/// Стол редактора: нажатие ставит биток или прицельный шар; для «чужого»/«свояка» рисуется мнимый шар.
struct SchemeEditorTable: View {
    @Binding var exercise: Exercise
    @Binding var mode: SchemePlaceMode
    var labels = false

    var body: some View {
        GeometryReader { geometry in
            TableSchemeView(exercise: exercise, labels: labels, showAim: true)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard let point = TableSchemeView.point(at: location, in: geometry.size, labels: labels) else { return }
                    place(point)
                }
        }
        .aspectRatio(labels ? 1.95 : 2.1, contentMode: .fit)
    }

    private func place(_ point: TablePoint) {
        let single = exercise.shot != nil
        switch mode {
        case .cue:
            if single { exercise.cueBalls = [point] } else { exercise.cueBalls.append(point) }
        case .object:
            if single { exercise.objectBalls = [point] } else { exercise.objectBalls.append(point) }
        }
        // После битка для «чужого»/«свояка» сразу предлагаем поставить прицельный шар
        if single, mode == .cue, exercise.objectBalls.isEmpty { mode = .object }
    }
}

/// Лупа: стол на весь экран (повёрнут вдоль экрана), повторное нажатие на лупу возвращает назад.
struct SchemeMagnifier: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercise: Exercise
    @Binding var mode: SchemePlaceMode

    var body: some View {
        VStack(spacing: Space.s) {
            HStack {
                Picker("Ставим", selection: $mode) {
                    ForEach(SchemePlaceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button { dismiss() } label: {
                    Image(systemName: "minus.magnifyingglass").font(.title2)
                }
                .accessibilityLabel("Уменьшить и вернуться")
            }
            .padding(.horizontal, Space.l)
            GeometryReader { geometry in
                let long = min(geometry.size.height, geometry.size.width * 1.95)
                let short = long / 1.95
                SchemeEditorTable(exercise: $exercise, mode: $mode, labels: true)
                    .frame(width: long, height: short)
                    .rotationEffect(.degrees(90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            HStack {
                Text(summary).font(.caption.monospacedDigit()).lineLimit(2)
                Spacer()
                Button("Отменить точку", systemImage: "arrow.uturn.backward") { undo() }
                    .font(.caption)
            }
            .padding(.horizontal, Space.l)
        }
        .padding(.vertical, Space.s)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private var summary: String {
        var parts = ["Биток: " + exercise.cueBalls.map { "\(Int($0.x)):\(Int($0.y))" }.joined(separator: ", ")]
        if !exercise.objectBalls.isEmpty {
            parts.append("Шар: " + exercise.objectBalls.map { "\(Int($0.x)):\(Int($0.y))" }.joined(separator: ", "))
        }
        if let aim = exercise.aim { parts.append("Мнимый: \(Int(aim.ghost.x)):\(Int(aim.ghost.y)), срез \(aim.cutDegrees)°") }
        return parts.joined(separator: " · ")
    }

    private func undo() {
        if mode == .object, !exercise.objectBalls.isEmpty { exercise.objectBalls.removeLast() }
        else if !exercise.cueBalls.isEmpty { exercise.cueBalls.removeLast() }
    }
}

/// Видео из галереи как файл.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Видео-урок тренера к упражнению: выбрать из галереи, посмотреть, убрать.
struct LessonVideoPicker: View {
    let container: AppContainer
    let exerciseId: String
    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        let file = container.backend.exerciseLessons[exerciseId]
        VStack(alignment: .leading, spacing: Space.s) {
            if let file {
                VideoPlayer(player: AVPlayer(url: DemoBackend.videoURL(file)))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            }
            HStack {
                PhotosPicker(selection: $item, matching: .videos) {
                    Label(file == nil ? "Добавить видео-урок" : "Заменить видео", systemImage: "video.badge.plus")
                }
                .buttonStyle(.cueSecondary)
                if loading { ProgressView() }
                if file != nil {
                    Button("Убрать", role: .destructive) {
                        container.backend.exerciseLessons[exerciseId] = nil
                        container.backend.save()
                    }
                    .buttonStyle(.cueSecondary)
                }
            }
            Text("Расскажите, как выполнять упражнение и на что обратить внимание. Ученики с Pro увидят урок в упражнении.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                if let movie = try? await newItem.loadTransferable(type: PickedMovie.self),
                   let name = container.backend.storeVideo(movie.url) {
                    container.backend.exerciseLessons[exerciseId] = name
                    container.backend.save()
                    container.backend.announceLesson(exerciseId: exerciseId, coachId: container.currentUserId)
                }
                loading = false
                item = nil
            }
        }
    }
}

/// Ручной редактор упражнения: название, описание, тип удара, метрика, луза; стол с лупой; видео-урок.
struct ExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var exercise: Exercise
    var container: AppContainer? = nil
    let onSave: (Exercise) -> Void
    @State private var details = ""
    @State private var mode: SchemePlaceMode = .cue
    @State private var magnified = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Упражнение") {
                    TextField("Название", text: $exercise.title)
                    TextField("Описание: координаты, винт, сколько ударов", text: $details, axis: .vertical).lineLimit(2...6)
                    Picker("Удар", selection: Binding(get: { exercise.shot }, set: { setShot($0) })) {
                        Text("По битку в лузу").tag(ShotKind?.none)
                        ForEach(ShotKind.allCases, id: \.self) { Text($0.title).tag(ShotKind?.some($0)) }
                    }
                    Picker("Метрика", selection: $exercise.metric) {
                        ForEach(MetricKey.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Ударов: \(exercise.attempts)", value: $exercise.attempts, in: 1...30)
                    Toggle("Отработка винта", isOn: $exercise.spin)
                    Toggle("Биток жёлтый (цветной)", isOn: Binding(get: { exercise.yellowCue == true }, set: { exercise.yellowCue = $0 ? true : nil }))
                }
                Section {
                    Toggle("Указать точку удара", isOn: Binding(get: { exercise.hitPoint != nil },
                                                                 set: { on in exercise.hitX = on ? 0 : nil; exercise.hitY = on ? 0 : nil }))
                    if exercise.hitPoint != nil {
                        HitPointPicker(point: Binding(get: { exercise.hitPoint ?? .zero },
                                                      set: { exercise.hitX = $0.x; exercise.hitY = $0.y }),
                                       yellow: exercise.yellowCue == true)
                    }
                } header: {
                    Text("Точка удара по битку")
                } footer: {
                    Text(exercise.shot == .ownBall ? "Для свояка точка удара меняет траекторию: мнимый шар пересчитается." : "Ученик увидит «прицел» с точкой удара, как в видеоуроках.")
                }
                Section {
                    Picker("Ставим", selection: $mode) {
                        ForEach(SchemePlaceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    SchemeEditorTable(exercise: $exercise, mode: $mode)
                        .overlay(alignment: .topTrailing) {
                            Button { magnified = true } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.headline)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .accessibilityLabel("Открыть стол крупно")
                        }
                    Picker("Луза", selection: Binding(get: { exercise.targets.first ?? .topMiddle }, set: { exercise.targets = [$0] })) {
                        Text("Верх · середина").tag(Pocket.topMiddle)
                        Text("Верх · левый угол").tag(Pocket.topLeft)
                        Text("Верх · правый угол").tag(Pocket.topRight)
                        Text("Низ · середина").tag(Pocket.bottomMiddle)
                        Text("Низ · левый угол").tag(Pocket.bottomLeft)
                        Text("Низ · правый угол").tag(Pocket.bottomRight)
                        if exercise.shot == nil { Text("Короткий борт").tag(Pocket.shortRail) }
                    }
                    Text(pointsText).font(.caption)
                    if let aim = exercise.aim {
                        Label("Мнимый шар \(Int(aim.ghost.x)):\(Int(aim.ghost.y)) · срез \(aim.cutDegrees)° · \(aim.thickness)", systemImage: "scope")
                            .font(.caption)
                    } else if exercise.shot != nil {
                        Text(exercise.objectBalls.isEmpty ? "Поставьте прицельный шар" : "Шар слишком близко к лузе — передвиньте")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("Убрать последнюю точку", role: .destructive) {
                        if mode == .object, !exercise.objectBalls.isEmpty { exercise.objectBalls.removeLast() }
                        else if !exercise.cueBalls.isEmpty { exercise.cueBalls.removeLast() }
                    }
                    .disabled(exercise.cueBalls.isEmpty && exercise.objectBalls.isEmpty)
                } header: {
                    Text("Схема")
                } footer: {
                    Text(exercise.shot == nil
                         ? "Нажмите на стол, чтобы поставить биток или шар. Лупа открывает стол крупно. Координаты — сетка 160×80."
                         : "Поставьте биток, затем прицельный шар — приложение нарисует мнимый шар: куда должен прийти биток, чтобы \(exercise.shot == .objectBall ? "забить чужой шар" : "сыграть свояка").")
                }
                if let container {
                    Section("Видео-урок") {
                        LessonVideoPicker(container: container, exerciseId: exercise.id)
                    }
                }
            }
            .navigationTitle("Упражнение №\(exercise.number)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { details = exercise.details.joined(separator: "\n") }
            .fullScreenCover(isPresented: $magnified) { SchemeMagnifier(exercise: $exercise, mode: $mode) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        exercise.details = details.split(separator: "\n").map(String.init)
                        onSave(exercise)
                        dismiss()
                    }
                    .disabled(exercise.title.trimmingCharacters(in: .whitespaces).isEmpty || exercise.cueBalls.isEmpty
                              || (exercise.shot != nil && exercise.aim == nil))
                }
            }
        }
    }

    private var pointsText: String {
        let cue: String = exercise.cueBalls.map { "\(Int($0.x)):\(Int($0.y))" }.joined(separator: ", ")
        let objects: String = exercise.objectBalls.map { "\(Int($0.x)):\(Int($0.y))" }.joined(separator: ", ")
        return objects.isEmpty ? "Биток: \(cue)" : "Биток: \(cue) · шар: \(objects)"
    }

    private func setShot(_ shot: ShotKind?) {
        exercise.shot = shot
        if let shot {
            exercise.metric = shot.metric
            exercise.cueBalls = Array(exercise.cueBalls.prefix(1))
            exercise.objectBalls = Array(exercise.objectBalls.prefix(1))
            if exercise.targets.first == .shortRail { exercise.targets = [.topRight] }
            mode = exercise.objectBalls.isEmpty ? .object : .cue
            if exercise.objectBalls.isEmpty { exercise.objectBalls = [TablePoint(x: 110, y: 25)] }
        }
    }
}
