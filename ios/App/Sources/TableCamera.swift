// App/Sources/TableCamera.swift — «Биток Про»: камера-помощник.
// 1) Расстановка: подсказывает, как отойти, чтобы весь стол был в кадре, показывает, куда клеить точки,
//    и в реальном времени проверяет, что шары стоят на местах (зелёный — ок, красный — ошибка с пояснением).
// 2) Выполнение на штативе (камера с противоположного борта): считает удары, ведёт запись, ставит звёзды,
//    показывает момент ошибки и совет; видео — в галерею, в приложение или тренеру; кусочек с ошибкой — тренеру.
// Алгоритм работает на устройстве: сукно ищется по цвету, шары — по яркости. Это демо-уровень компьютерного зрения;
// в проде — обученная модель (Core ML) для стола, шаров и кия.
import SwiftUI
import AVFoundation
import AVKit
import Photos
import CoreDomain
import DesignSystem

// MARK: - Анализ кадра

/// Четырёхугольник стола в нормализованных координатах кадра (0…1): углы по часовой, начиная с «дальнего левого».
struct TableQuad: Equatable {
    var tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint

    /// Точка стола (x 0…160 вдоль длинной стороны, y 0…80) → точка кадра (билинейно).
    func project(_ p: TablePoint) -> CGPoint {
        let u = p.x / 160, v = p.y / 80
        let top = CGPoint(x: tl.x + (tr.x - tl.x) * u, y: tl.y + (tr.y - tl.y) * u)
        let bottom = CGPoint(x: bl.x + (br.x - bl.x) * u, y: bl.y + (br.y - bl.y) * u)
        return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
    }

    /// Обратное преобразование (несколько итераций Ньютона).
    func unproject(_ q: CGPoint) -> TablePoint {
        var u = 0.5, v = 0.5
        for _ in 0..<8 {
            let p = project(TablePoint(x: u * 160, y: v * 80))
            let du = project(TablePoint(x: min(160, u * 160 + 1), y: v * 80))
            let dv = project(TablePoint(x: u * 160, y: min(80, v * 80 + 1)))
            let a = (du.x - p.x) * 160, b = (dv.x - p.x) * 80, c = (du.y - p.y) * 160, d = (dv.y - p.y) * 80
            let det = a * d - b * c
            guard abs(det) > 1e-9 else { break }
            let ex = q.x - p.x, ey = q.y - p.y
            u += (d * ex - b * ey) / det
            v += (-c * ex + a * ey) / det
        }
        return TablePoint(x: u * 160, y: v * 80)
    }

    var area: CGFloat {
        let pts = [tl, tr, br, bl]
        var sum: CGFloat = 0
        for i in 0..<4 { let a = pts[i], b = pts[(i + 1) % 4]; sum += a.x * b.y - b.x * a.y }
        return abs(sum) / 2
    }
}

/// Уменьшенная копия кадра: маска сукна и маска шаров.
/// Сукно ищется по преобладающему оттенку (зелёное, бирюзовое, синее) и берётся только самое большое
/// связное пятно — так зелёные лампы, стены и соседние столы не путаются со столом.
struct FrameGrid {
    let width: Int, height: Int
    var green: [Bool]
    var bright: [Bool]
    /// Сколько клеток минимум должно быть у шара (наклейка-точка намного меньше шара).
    var minBlob = 2

    init?(_ buffer: CVPixelBuffer, columns: Int = 200) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let step = max(1, w / columns)
        width = w / step
        height = h / step
        let count = width * height
        var hues = [Float](repeating: 0, count: count)
        var candidate = [Bool](repeating: false, count: count)
        var histogram = [Double](repeating: 0, count: 36)
        bright = Array(repeating: false, count: count)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        for gy in 0..<height {
            for gx in 0..<width {
                let offset = gy * step * row + gx * step * 4
                let b = Int(pointer[offset]), g = Int(pointer[offset + 1]), r = Int(pointer[offset + 2])
                let (hue, saturation, value) = Self.hsv(r, g, b)
                let index = gy * width + gx
                hues[index] = hue
                if hue >= 90, hue <= 250, saturation > 0.25, value > 0.18 {
                    candidate[index] = true
                    // Стол обычно в нижней части кадра — ей больше веса
                    histogram[min(35, Int(hue / 10))] += 0.4 + Double(gy) / Double(height)
                }
                // Белый/кремовый шар или жёлтый биток
                let white = r + g + b > 540 && saturation < 0.22
                let yellow = hue >= 35 && hue <= 65 && saturation > 0.45 && value > 0.6
                bright[index] = white || yellow
            }
        }
        var peakBin = 0, peakScore = -1.0
        for bin in 0..<36 {
            let score = histogram[bin] + 0.5 * (histogram[(bin + 35) % 36] + histogram[(bin + 1) % 36])
            if score > peakScore { peakScore = score; peakBin = bin }
        }
        let peak = Float(peakBin * 10 + 5)
        var mask = [Bool](repeating: false, count: count)
        for index in 0..<count where candidate[index] && abs(hues[index] - peak) <= 22 { mask[index] = true }
        green = Self.largestComponent(mask, width: width, height: height)
    }

    static func hsv(_ r: Int, _ g: Int, _ b: Int) -> (Float, Float, Float) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = Float(maxV - minV)
        let value = Float(maxV) / 255
        let saturation = maxV == 0 ? 0 : delta / Float(maxV)
        guard delta > 0 else { return (0, saturation, value) }
        var hue: Float
        if maxV == r { hue = 60 * Float(g - b) / delta } else if maxV == g { hue = 60 * Float(b - r) / delta + 120 } else { hue = 60 * Float(r - g) / delta + 240 }
        if hue < 0 { hue += 360 }
        return (hue, saturation, value)
    }

    /// Самое большое связное пятно маски.
    static func largestComponent(_ mask: [Bool], width: Int, height: Int) -> [Bool] {
        var label = [Int32](repeating: 0, count: mask.count)
        var bestLabel: Int32 = 0, bestSize = 0, current: Int32 = 0
        var stack: [Int] = []
        for start in 0..<mask.count where mask[start] && label[start] == 0 {
            current += 1
            label[start] = current
            stack.append(start)
            var size = 0
            while let index = stack.popLast() {
                size += 1
                let x = index % width, y = index / width
                if x > 0, mask[index - 1], label[index - 1] == 0 { label[index - 1] = current; stack.append(index - 1) }
                if x < width - 1, mask[index + 1], label[index + 1] == 0 { label[index + 1] = current; stack.append(index + 1) }
                if y > 0, mask[index - width], label[index - width] == 0 { label[index - width] = current; stack.append(index - width) }
                if y < height - 1, mask[index + width], label[index + width] == 0 { label[index + width] = current; stack.append(index + width) }
            }
            if size > bestSize { bestSize = size; bestLabel = current }
        }
        return label.map { $0 == bestLabel && bestLabel != 0 }
    }

    func quad() -> (TableQuad, Double)? {
        var count = 0
        var tl = (Int.max, CGPoint.zero), br = (Int.min, CGPoint.zero), tr = (Int.min, CGPoint.zero), bl = (Int.max, CGPoint.zero)
        for y in 0..<height {
            for x in 0..<width where green[y * width + x] {
                count += 1
                let p = CGPoint(x: Double(x) / Double(width), y: Double(y) / Double(height))
                if x + y < tl.0 { tl = (x + y, p) }
                if x + y > br.0 { br = (x + y, p) }
                if x - y > tr.0 { tr = (x - y, p) }
                if x - y < bl.0 { bl = (x - y, p) }
            }
        }
        let fraction = Double(count) / Double(width * height)
        guard fraction > 0.06 else { return nil }
        var quad = TableQuad(tl: tl.1, tr: tr.1, br: br.1, bl: bl.1)
        // Длинная сторона стола должна идти по «x» схемы.
        let top = hypot(quad.tr.x - quad.tl.x, quad.tr.y - quad.tl.y)
        let left = hypot(quad.bl.x - quad.tl.x, quad.bl.y - quad.tl.y)
        if left > top * 1.15 { quad = TableQuad(tl: quad.bl, tr: quad.tl, br: quad.tr, bl: quad.br) }
        return (quad, fraction)
    }

    /// Центр светлого пятна рядом с точкой (радиус в долях ширины кадра).
    func brightBlob(near point: CGPoint, radius: Double) -> CGPoint? {
        let cx = Int(point.x * Double(width)), cy = Int(point.y * Double(height))
        let r = max(1, Int(radius * Double(width)))
        var sx = 0, sy = 0, n = 0
        for y in max(0, cy - r)...min(height - 1, cy + r) {
            for x in max(0, cx - r)...min(width - 1, cx + r) where bright[y * width + x] {
                sx += x; sy += y; n += 1
            }
        }
        guard n >= minBlob else { return nil }
        return CGPoint(x: Double(sx) / Double(n) / Double(width), y: Double(sy) / Double(n) / Double(height))
    }
}

// MARK: - Камера

enum MarkStatus: Equatable { case unknown, ok, missing, off(String) }

struct ShotEvent: Identifiable, Equatable {
    let id = UUID()
    let time: Double          // секунда записи
    let made: Bool
    let advice: String
}

final class TableCameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Hint: Equatable {
        case noTable, stepBack, closer, tilt, ready
        var text: String {
            switch self {
            case .noTable: "Наведите камеру на стол — нужно видеть сукно целиком"
            case .stepBack: "Отойдите назад: стол не помещается в кадр целиком"
            case .closer: "Подойдите ближе: стол слишком маленький"
            case .tilt: "Поднимите телефон выше и наклоните к столу"
            case .ready: "Стол в кадре ✓ Держите телефон ровно"
            }
        }
    }

    @Published var quad: TableQuad?
    @Published var hint: Hint = .noTable
    @Published var marks: [MarkStatus] = []
    @Published var isAuthorized = true
    @Published var recording = false
    @Published var shots: [ShotEvent] = []
    @Published var cueSeen: CGPoint?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "bitok.camera")
    private var exercise: Exercise
    private var lastAnalysis = Date.distantPast
    private var smoothed: TableQuad?

    // Запись
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var recordStart: CMTime?
    private(set) var videoURL: URL?

    // Слежение за ударом
    private enum ShotState { case waiting, moving(since: Date, last: CGPoint) }
    private var shotState: ShotState = .waiting
    private var stillSince: Date?

    init(exercise: Exercise) {
        self.exercise = exercise
        super.init()
        marks = Array(repeating: .unknown, count: exercise.markPoints.count)
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.isAuthorized = granted }
                if granted { self.configure() }
            }
        default: isAuthorized = false
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    /// Демо без камеры (симулятор, скриншоты «Помощи»): стол в перспективе, часть шаров на местах.
    func startDemo(perform: Bool) {
        isAuthorized = true
        let demoQuad = TableQuad(tl: CGPoint(x: 0.16, y: 0.30), tr: CGPoint(x: 0.84, y: 0.30),
                                 br: CGPoint(x: 0.97, y: 0.62), bl: CGPoint(x: 0.03, y: 0.62))
        quad = demoQuad
        hint = .ready
        marks = exercise.markPoints.enumerated().map { index, _ in
            index == 1 ? .off("Сдвиньте шар на 3 см к правому борту") : index == 3 ? .missing : .ok
        }
        if perform {
            recording = true
            shots = [ShotEvent(time: 4, made: true, advice: Self.praise[0]),
                     ShotEvent(time: 11, made: false, advice: Self.advice(start: TablePoint(x: 70, y: 40), target: TablePoint(x: 80, y: 0),
                                                                         end: TablePoint(x: 66, y: 4))),
                     ShotEvent(time: 18, made: true, advice: Self.praise[1])]
        }
    }

    private func configure() {
        queue.async {
            guard self.session.inputs.isEmpty,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            if self.session.canAddInput(input) { self.session.addInput(input) }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(output) { self.session.addOutput(output) }
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // кадр в портретной ориентации, как превью
            }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    // MARK: Запись видео выполнения

    func startRecording() {
        queue.async {
            let url = URL.temporaryDirectory.appending(path: "bitok-\(UUID().uuidString).mov")
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 720, AVVideoHeightKey: 1280,
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input) }
            self.writer = writer
            self.writerInput = input
            self.recordStart = nil
            self.videoURL = url
            self.shotState = .waiting
            DispatchQueue.main.async {
                self.shots = []
                self.recording = true
            }
        }
    }

    func stopRecording(_ completion: @escaping (URL?) -> Void) {
        queue.async {
            guard let writer = self.writer, writer.status == .writing else {
                DispatchQueue.main.async { self.recording = false; completion(nil) }
                return
            }
            self.writerInput?.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    self.recording = false
                    completion(writer.status == .completed ? self.videoURL : nil)
                }
            }
            self.writer = nil
        }
    }

    private var recordSeconds: Double {
        guard let start = recordStart else { return 0 }
        return CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) - CMTimeGetSeconds(start)
    }

    // MARK: Кадры

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let writer, let input = writerInput {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: time)
                recordStart = CMClockGetTime(CMClockGetHostTimeClock())
            }
            if writer.status == .writing && input.isReadyForMoreMediaData { input.append(sampleBuffer) }
        }
        guard Date().timeIntervalSince(lastAnalysis) > 0.15, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let grid = FrameGrid(buffer) else { return }
        lastAnalysis = Date()
        analyze(grid)
    }

    private func analyze(_ frame: FrameGrid) {
        var grid = frame
        guard let (raw, fraction) = grid.quad() else {
            DispatchQueue.main.async { self.quad = nil; self.hint = .noTable }
            return
        }
        // Сглаживание, чтобы разметка не дрожала
        let quad: TableQuad
        if let previous = smoothed {
            func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x * 0.7 + b.x * 0.3, y: a.y * 0.7 + b.y * 0.3) }
            quad = TableQuad(tl: mix(previous.tl, raw.tl), tr: mix(previous.tr, raw.tr), br: mix(previous.br, raw.br), bl: mix(previous.bl, raw.bl))
        } else {
            quad = raw
        }
        smoothed = quad
        let edge: CGFloat = 0.02
        let corners: [CGPoint] = [quad.tl, quad.tr, quad.br, quad.bl]
        var touches = false
        for corner in corners where corner.x < edge || corner.x > 1 - edge || corner.y < edge || corner.y > 1 - edge {
            touches = true
        }
        let hint: Hint
        if touches { hint = .stepBack } else if fraction < 0.12 { hint = .closer } else if quad.area < 0.12 { hint = .tilt } else { hint = .ready }

        // Шары на точках
        let topEdge: CGFloat = hypot(quad.tr.x - quad.tl.x, quad.tr.y - quad.tl.y)
        let ballRadius: Double = max(0.012, Double(topEdge) / 160 * 3.4)
        // Шар ≈ 3 единицы схемы в диаметре; наклейка-точка в разы меньше — её за шар не считаем
        let ballCells = Double(topEdge) * Double(grid.width) / 160 * 1.6
        grid.minBlob = max(2, Int(0.3 * Double.pi * ballCells * ballCells))
        let statuses: [MarkStatus] = exercise.markPoints.map { point in
            let projected = quad.project(point)
            if grid.brightBlob(near: projected, radius: ballRadius * 1.3) != nil { return .ok }
            if let nearby = grid.brightBlob(near: projected, radius: ballRadius * 5) {
                let actual = quad.unproject(nearby)
                let dx = point.x - actual.x, dy = point.y - actual.y
                var parts: [String] = []
                if abs(dx) > 2 { parts.append("на \(Int(abs(dx).rounded())) см \(dx > 0 ? "дальше к правому борту" : "ближе к левому борту")") }
                if abs(dy) > 2 { parts.append("на \(Int(abs(dy).rounded())) см \(dy > 0 ? "к нижнему борту" : "к верхнему борту")") }
                return .off(parts.isEmpty ? "Чуть поправьте шар на точку" : "Сдвиньте шар " + parts.joined(separator: " и "))
            }
            return .missing
        }

        // Слежение за битком во время записи
        let start = quad.project(exercise.cueBalls.first ?? TablePoint(x: 70, y: 40))
        let cue = grid.brightBlob(near: start, radius: ballRadius * 1.4)
        if writer != nil { trackShot(grid: grid, quad: quad, startSeen: cue != nil, radius: ballRadius) }

        DispatchQueue.main.async {
            self.quad = quad
            self.hint = hint
            self.marks = statuses
            self.cueSeen = cue
        }
    }

    /// Удар: биток ушёл с точки → движется → исчез у лузы (забит) или остановился в стороне (промах).
    private func trackShot(grid: FrameGrid, quad: TableQuad, startSeen: Bool, radius: Double) {
        let startPoint = exercise.cueBalls.first ?? TablePoint(x: 70, y: 40)
        let target = exercise.targetPoint(for: 0) ?? Pocket.topMiddle.point
        switch shotState {
        case .waiting:
            if !startSeen, let moved = grid.brightBlob(near: quad.project(startPoint), radius: radius * 8) {
                shotState = .moving(since: Date(), last: moved)
                stillSince = nil
            }
        case .moving(let since, let last):
            if let now = grid.brightBlob(near: last, radius: radius * 6) {
                let speed = hypot(now.x - last.x, now.y - last.y)
                if speed < radius * 0.15 {
                    stillSince = stillSince ?? Date()
                    if Date().timeIntervalSince(stillSince!) > 1.0 {
                        finishShot(made: false, endPoint: quad.unproject(now), start: startPoint, target: target)
                    }
                } else {
                    stillSince = nil
                }
                shotState = .moving(since: since, last: now)
            } else if Date().timeIntervalSince(since) > 0.3 {
                // Пропал из кадра: если был у лузы — забит.
                let end = quad.unproject(last)
                let nearPocket = hypot(end.x - target.x, end.y - target.y) < 18
                finishShot(made: nearPocket, endPoint: end, start: startPoint, target: target)
            }
        }
    }

    private func finishShot(made: Bool, endPoint: TablePoint, start: TablePoint, target: TablePoint) {
        shotState = .waiting
        stillSince = nil
        let advice = made ? Self.praise.randomElement()! : Self.advice(start: start, target: target, end: endPoint)
        let event = ShotEvent(time: max(0, recordSeconds - 1.5), made: made, advice: advice)
        DispatchQueue.main.async { self.shots.append(event) }
    }

    static let praise = ["Отличный удар! 🔥", "Чисто! Так держать", "Есть! Рука стабильная", "Красиво! Ещё один такой же"]

    static let motivation = ["Всё получится — каждый удар делает руку точнее", "Дыши ровно, смотри на прицел, а не на кий",
                             "Чемпионы тоже мажут — главное повторять", "Ты уже лучше, чем на прошлой неделе 💪",
                             "Спокойно: стойка, пауза, удар", "Ещё немного — и это упражнение станет лёгким"]

    /// Совет по промаху: куда ушёл биток относительно линии прицела.
    static func advice(start: TablePoint, target: TablePoint, end: TablePoint) -> String {
        let aim = (x: target.x - start.x, y: target.y - start.y)
        let shot = (x: end.x - start.x, y: end.y - start.y)
        let cross = aim.x * shot.y - aim.y * shot.x
        let aimLength = hypot(aim.x, aim.y), shotLength = hypot(shot.x, shot.y)
        if shotLength < aimLength * 0.6 {
            return "Не хватило силы: биток остановился, не дойдя до лузы. Доведите кий после удара и сделайте плавный разгон."
        }
        if cross > 0 {
            return "Биток ушёл правее лузы. Проверьте, что локоть идёт вертикально и кий не уводится в сторону; целитесь в центр лузы."
        }
        return "Биток ушёл левее лузы. Задержите паузу перед ударом, держите голову неподвижно и не поднимайте её до конца удара."
    }
}

/// Превью камеры.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Экран камеры

struct TableCameraTrainer: View {
    enum Mode: String, CaseIterable, Identifiable {
        case setup = "Расстановка", perform = "Выполнение"
        var id: Self { self }
    }
    enum Phase { case framing, marks, balls }

    @Environment(\.dismiss) private var dismiss
    let container: AppContainer
    let exercise: Exercise
    /// Демо-кадр вместо камеры: framing, marks, balls, perform.
    var demo: String? = nil
    @StateObject private var camera: TableCameraModel
    @State private var mode: Mode = .setup
    @State private var phase: Phase = .framing
    @State private var pulse = false
    @State private var motivation = TableCameraModel.motivation[0]
    @State private var result: TrainingResult?
    @State private var celebrated = false

    init(container: AppContainer, exercise: Exercise, demo: String? = nil) {
        self.container = container
        self.exercise = exercise
        self.demo = demo
        _camera = StateObject(wrappedValue: TableCameraModel(exercise: exercise))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if demo != nil {
                    demoTable(size: geometry.size).ignoresSafeArea()
                    overlay(size: geometry.size).ignoresSafeArea().allowsHitTesting(false)
                } else if camera.isAuthorized {
                    CameraPreview(session: camera.session).ignoresSafeArea()
                    overlay(size: geometry.size).ignoresSafeArea().allowsHitTesting(false)
                } else {
                    Text("Разрешите доступ к камере: Настройки → Биток → Камера").foregroundStyle(.white).padding()
                }
                VStack(spacing: Space.m) {
                    topBar
                    Spacer()
                    bottomPanel
                }
                .padding(Space.l)
            }
        }
        .onAppear {
            if let demo {
                camera.startDemo(perform: demo == "perform")
                switch demo {
                case "marks": phase = .marks
                case "balls": phase = .balls
                case "perform": mode = .perform
                default: phase = .framing
                }
            } else {
                camera.start()
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true }
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.marks) { _, marks in
            if phase == .balls, !marks.isEmpty, marks.allSatisfy({ $0 == .ok }), !celebrated {
                celebrated = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: camera.shots.count) { _, _ in
            motivation = TableCameraModel.motivation.randomElement()!
            UIImpactFeedbackGenerator(style: camera.shots.last?.made == true ? .medium : .light).impactOccurred()
        }
        .fullScreenCover(item: $result) { item in
            TrainingResultView(container: container, exercise: exercise, result: item) { dismiss() }
        }
    }

    /// Нарисованный стол для демо: комната, сукно в перспективе, шары на точках (один сдвинут, одного нет).
    private func demoTable(size: CGSize) -> some View {
        Canvas { context, _ in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(white: 0.18), Color(white: 0.08)]), startPoint: .zero,
                                               endPoint: CGPoint(x: 0, y: size.height)))
            guard let quad = camera.quad else { return }
            let corners: [CGPoint] = [quad.tl, quad.tr, quad.br, quad.bl].map { toScreen($0, size: size) }
            var rails = Path()
            rails.addLines([CGPoint(x: corners[0].x - 14, y: corners[0].y - 12), CGPoint(x: corners[1].x + 14, y: corners[1].y - 12),
                            CGPoint(x: corners[2].x + 20, y: corners[2].y + 16), CGPoint(x: corners[3].x - 20, y: corners[3].y + 16)])
            rails.closeSubpath()
            context.fill(rails, with: .color(Color(red: 0.42, green: 0.25, blue: 0.08)))
            var felt = Path()
            felt.addLines(corners)
            felt.closeSubpath()
            context.fill(felt, with: .color(Color(red: 0.16, green: 0.52, blue: 0.22)))
            for (index, point) in exercise.markPoints.enumerated() {
                guard index != 3 else { continue }
                var p = quad.project(point)
                if index == 1 { p = quad.project(TablePoint(x: point.x - 3, y: point.y + 1)) }
                let c = toScreen(p, size: size)
                let r: CGFloat = 9
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.97)))
            }
        }
    }

    // Пересчёт нормализованных координат кадра в координаты экрана (превью «заполняет» экран).
    private func toScreen(_ p: CGPoint, size: CGSize) -> CGPoint {
        let frameAspect: CGFloat = 720.0 / 1280.0
        let viewAspect = size.width / size.height
        if viewAspect > frameAspect {
            let height = size.width / frameAspect
            return CGPoint(x: p.x * size.width, y: p.y * height - (height - size.height) / 2)
        }
        let width = size.height * frameAspect
        return CGPoint(x: p.x * width - (width - size.width) / 2, y: p.y * size.height)
    }

    private func overlay(size: CGSize) -> some View {
        Canvas { context, _ in
            guard let quad = camera.quad else { return }
            var outline = Path()
            let outlinePoints: [CGPoint] = [quad.tl, quad.tr, quad.br, quad.bl, quad.tl].map { toScreen($0, size: size) }
            outline.addLines(outlinePoints)
            context.stroke(outline, with: .color(camera.hint == .ready ? .green : .yellow), lineWidth: 3)
            guard phase != .framing || mode == .perform else { return }
            let screenTL: CGPoint = toScreen(quad.tl, size: size)
            let screenTR: CGPoint = toScreen(quad.tr, size: size)
            let edge: CGFloat = hypot(screenTR.x - screenTL.x, screenTR.y - screenTL.y)
            let pulseScale: CGFloat = pulse ? 1.25 : 1
            let r: CGFloat = max(8, edge / 160 * 3.4) * pulseScale
            // Линия удара
            if let first = exercise.cueBalls.first, let target = exercise.targetPoint(for: 0) {
                var line = Path()
                line.move(to: toScreen(quad.project(first), size: size))
                line.addLine(to: toScreen(quad.project(target), size: size))
                context.stroke(line, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            for (index, point) in exercise.markPoints.enumerated() {
                let c = toScreen(quad.project(point), size: size)
                let status = index < camera.marks.count ? camera.marks[index] : .unknown
                let color: Color = phase == .marks ? .cyan : status == .ok ? .green : .red
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.black.opacity(0.4), in: Circle())
            }
            Picker("Режим", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
                .disabled(camera.recording)
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("№\(exercise.number) · \(exercise.title)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            switch mode {
            case .setup: setupPanel
            case .perform: performPanel
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var setupPanel: some View {
        switch phase {
        case .framing:
            Label(camera.hint.text, systemImage: camera.hint == .ready ? "checkmark.circle.fill" : "arrow.up.and.down.and.arrow.left.and.right")
                .font(.headline).foregroundStyle(camera.hint == .ready ? .green : .yellow)
            Text("Встаньте у короткого борта так, чтобы весь стол русского бильярда был в кадре.").font(.caption).foregroundStyle(.white)
            Button("Дальше: точки для шаров") { phase = .marks }
                .buttonStyle(.cueGlassProminent)
                .disabled(camera.hint != .ready)
        case .marks:
            Text("Наклейте точки там, где светятся голубые круги").font(.headline).foregroundStyle(.cyan)
            Text(exercise.markPoints.prefix(6).map { "\(Int($0.x)):\(Int($0.y))" }.joined(separator: " · ")).font(.caption.monospaced())
                .foregroundStyle(.white)
            Button("Наклеил(а) — ставлю шары") { phase = .balls }.buttonStyle(.cueGlassProminent)
        case .balls:
            let okCount = camera.marks.filter { $0 == .ok }.count
            if okCount == camera.marks.count && !camera.marks.isEmpty {
                Label("Всё стоит правильно! Можно бить 🎱", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                Button("Перейти к выполнению") { mode = .perform }.buttonStyle(.cueGlassProminent)
            } else {
                Text("На местах: \(okCount) из \(camera.marks.count)").font(.headline).foregroundStyle(.white)
                ForEach(Array(camera.marks.enumerated()).prefix(4), id: \.offset) { index, status in
                    switch status {
                    case .off(let text): Label(text, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    case .missing:
                        let p = exercise.markPoints[index]
                        Label("Поставьте шар на точку \(Int(p.x)):\(Int(p.y))", systemImage: "circle.dashed").font(.caption).foregroundStyle(.red)
                    default: EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var performPanel: some View {
        let made = camera.shots.filter(\.made).count
        if camera.recording {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10).opacity(pulse ? 1 : 0.3)
                Text("Запись · удары \(camera.shots.count)/\(exercise.attempts) · забито \(made)").font(.headline).foregroundStyle(.white)
            }
            if let last = camera.shots.last {
                Text(last.made ? last.advice : "Промах. \(last.advice)").font(.callout).foregroundStyle(last.made ? .green : .orange)
            }
            Text(motivation).font(.caption).foregroundStyle(.white.opacity(0.85))
            Button("Завершить") { finish() }.buttonStyle(.cueGlassProminent)
        } else {
            Text("Поставьте телефон на штатив напротив себя, у противоположного борта. Камера посчитает удары и подскажет ошибки.")
                .font(.callout).foregroundStyle(.white)
            HStack(alignment: .top, spacing: Space.s) {
                TableSchemeView(exercise: exercise, labels: false, showTripod: true).frame(width: 110)
                Text(exercise.tripod.hint).font(.caption).foregroundStyle(.white.opacity(0.9))
            }
            Label(camera.hint.text, systemImage: "camera.viewfinder").font(.caption).foregroundStyle(camera.hint == .ready ? .green : .yellow)
            Button { camera.startRecording() } label: { Label("Начать запись", systemImage: "record.circle") }
                .buttonStyle(.cueGlassProminent)
                .disabled(camera.hint != .ready)
        }
    }

    private func finish() {
        let shots = camera.shots
        camera.stopRecording { url in
            result = TrainingResult(videoURL: url, shots: shots, attempts: max(exercise.attempts, shots.count))
        }
    }
}

// MARK: - Итог выполнения

struct TrainingResult: Identifiable {
    let id = UUID()
    let videoURL: URL?
    let shots: [ShotEvent]
    let attempts: Int

    var made: Int { shots.filter(\.made).count }
    var percent: Int { attempts == 0 ? 0 : made * 100 / attempts }
    /// Звёзды: 3 — от 80%, 2 — от 60%, 1 — от 40%.
    var stars: Int { percent >= 80 ? 3 : percent >= 60 ? 2 : percent >= 40 ? 1 : 0 }
}

struct TrainingResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let exercise: Exercise
    let result: TrainingResult
    let onClose: () -> Void
    @State private var player: AVPlayer?
    @State private var info: String?
    @State private var savedLocally = false

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }
    private var coachId: UserID? { backend.coachesOf(me).first?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(spacing: Space.s) {
                        HStack(spacing: 6) {
                            ForEach(0..<3) { index in
                                Image(systemName: index < result.stars ? "star.fill" : "star")
                                    .font(.system(size: 40)).foregroundStyle(.yellow)
                            }
                        }
                        Text("Забито \(result.made) из \(result.attempts) · \(result.percent)%").font(.title3.weight(.bold))
                        Text(result.stars >= 2 ? "Отлично! Упражнение засчитано ⭐️" : "Всё получится — разберём ошибки и попробуем ещё раз 💪")
                            .font(.callout).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Space.l)
                    .glassCard()

                    if let player {
                        VideoPlayer(player: player).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: Radius.l))
                    }

                    let misses = result.shots.filter { !$0.made }
                    if !misses.isEmpty {
                        Text("Ошибки на видео").font(.headline)
                        ForEach(misses) { shot in
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Button {
                                    player?.seek(to: CMTime(seconds: shot.time, preferredTimescale: 600))
                                    player?.play()
                                } label: {
                                    Label("Смотреть момент \(timeLabel(shot.time))", systemImage: "play.circle.fill")
                                }
                                .font(.callout.weight(.semibold))
                                Text(shot.advice).font(.callout)
                                if misses.count >= 2, let coachId {
                                    Button {
                                        sendClip(around: shot, to: coachId)
                                    } label: {
                                        Label("Не получается — отправить этот кусочек тренеру", systemImage: "paperplane")
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                        }
                    }

                    if result.videoURL != nil {
                        VStack(spacing: Space.s) {
                            if let coachId {
                                Button {
                                    sendFull(to: coachId)
                                } label: {
                                    Label("Отправить видео тренеру (\(backend.name(coachId)))", systemImage: "paperplane.fill")
                                }
                                .buttonStyle(.cueGlassProminent)
                            }
                            Button { saveToPhotos() } label: { Label("Сохранить в галерею", systemImage: "photo.on.rectangle") }
                                .buttonStyle(.cueSecondary)
                            Button { saveInApp() } label: {
                                Label(savedLocally ? "Сохранено в приложении ✓" : "Сохранить в приложении", systemImage: "tray.and.arrow.down")
                            }
                            .buttonStyle(.cueSecondary)
                            .disabled(savedLocally)
                        }
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle("Результат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                        onClose()
                    }
                }
            }
            .errorAlert($info, title: "Готово")
            .onAppear {
                if let url = result.videoURL { player = AVPlayer(url: url) }
                backend.recordTraining(exercise: exercise, studentId: me, made: result.made, attempts: result.attempts, stars: result.stars)
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func saveInApp() {
        guard let url = result.videoURL, let saved = backend.storeVideo(url) else { return }
        backend.attachVideo(saved, exercise: exercise, studentId: me)
        savedLocally = true
    }

    private func saveToPhotos() {
        guard let url = result.videoURL else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in info = "Разрешите доступ к фото: Настройки → Биток → Фото" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, _ in
                Task { @MainActor in info = ok ? "Видео сохранено в галерею" : "Не удалось сохранить видео" }
            }
        }
    }

    private func sendFull(to coachId: UserID) {
        guard let url = result.videoURL, let saved = backend.storeVideo(url) else { return }
        backend.sendVideo(saved, from: me, to: coachId,
                          text: "Выполнил(а) упражнение №\(exercise.number): забито \(result.made) из \(result.attempts) \(String(repeating: "⭐️", count: result.stars))")
        info = "Видео отправлено тренеру в чат"
    }

    /// Кусочек ±4 секунды вокруг ошибки.
    private func sendClip(around shot: ShotEvent, to coachId: UserID) {
        guard let url = result.videoURL else { return }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { return }
        let output = URL.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        export.timeRange = CMTimeRange(start: CMTime(seconds: max(0, shot.time - 4), preferredTimescale: 600),
                                       duration: CMTime(seconds: 8, preferredTimescale: 600))
        export.exportAsynchronously {
            Task { @MainActor in
                guard export.status == .completed, let saved = backend.storeVideo(output) else {
                    info = "Не удалось вырезать фрагмент"
                    return
                }
                backend.sendVideo(saved, from: me, to: coachId,
                                  text: "Тут не получается — упражнение №\(exercise.number). \(shot.advice) Подскажите, что поправить?")
                info = "Фрагмент с ошибкой отправлен тренеру"
            }
        }
    }
}

// MARK: - Подписка

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    var onSubscribed: () -> Void = {}
    @State private var yearly = true
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 64)).foregroundStyle(palette.accent).padding(.top, Space.l)
                    Text("Биток Про").font(.largeTitle.weight(.bold)).fontDesign(palette.headingDesign)
                    VStack(alignment: .leading, spacing: Space.m) {
                        feature("viewfinder", "Камера находит стол и подсказывает, как встать")
                        feature("smallcircle.filled.circle", "Показывает, куда клеить точки и ставить шары")
                        feature("checkmark.seal", "Проверяет расстановку в реальном времени и объясняет ошибки")
                        feature("video", "Режим на штативе: считает удары, звёзды за упражнение")
                        feature("exclamationmark.bubble", "Показывает момент ошибки и как исправить")
                        feature("paperplane", "Видео и кусочек с ошибкой — тренеру в чат")
                        feature("person.3.sequence", "Групповые чаты с друзьями и тренером")
                        feature("scope", "Чужой шар и свояк: мнимый шар, срез и как бить")
                        feature("play.rectangle", "Видео-уроки тренера к упражнениям")
                        feature("sparkles", "Оформление профиля: фоны карточки, редкие рамки, значок PRO и статус")
                    }
                    .padding(Space.l)
                    .glassCard()
                    let youth = container.backend.hasYouthDiscount(container.currentUserId)
                    if youth {
                        Label("Вам меньше 14 лет — подписка за полцены 🎉", systemImage: "graduationcap.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(palette.accent)
                    }
                    VStack(spacing: Space.s) {
                        plan(title: "Год", price: youth ? "1 245 ₽" : "2 490 ₽",
                             note: youth ? "104 ₽ в месяц · скидка 50% до 14 лет" : "207 ₽ в месяц · выгода 30%", selected: yearly) { yearly = true }
                        plan(title: "Месяц", price: youth ? "149 ₽" : "299 ₽",
                             note: youth ? "Скидка 50% для учеников младше 14 лет" : "Отмена в любой момент", selected: !yearly) { yearly = false }
                    }
                    if !youth {
                        Text("Ученикам младше 14 лет — скидка 50% (укажите дату рождения в профиле)").font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("Демо-режим: оплата не списывается. В приложении из App Store — покупка через Apple, на Android — через Google Play.")
                        .font(.caption).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                }
                .padding(Space.l)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Оформить \(yearly ? "на год" : "на месяц")") {
                    container.backend.subscribe(container.currentUserId, months: yearly ? 12 : 1)
                    showWelcome = true
                }
                .buttonStyle(.cueGlassProminent)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)
            }
            .background(ThemedBackground())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .sheet(isPresented: $showWelcome, onDismiss: { dismiss() }) {
                ProWelcomeView { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onSubscribed() } }
            }
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.callout)
    }

    private func plan(title: String, price: String, note: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(palette.accent)
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(note).font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text(price).font(.title3.bold())
            }
            .padding(Space.m)
            .glassCard()
            .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(selected ? palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
