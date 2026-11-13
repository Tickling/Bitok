// App/Sources/Exercises.swift — упражнения (подготовительный уровень), схема стола, результаты,
// статистика ученика и сравнение двух учеников.
import SwiftUI
import Charts
import AVKit
import CoreDomain
import DesignSystem
import ProgressDomain

// MARK: - Модель

/// Точка на столе русского бильярда в сантиметровой сетке схемы: x 0…160 (длинный борт), y 0…80 (короткий).
struct TablePoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

enum Pocket: String, Codable, CaseIterable, Sendable {
    case topLeft, topMiddle, topRight, bottomLeft, bottomMiddle, bottomRight, shortRail

    var point: TablePoint {
        switch self {
        case .topLeft: TablePoint(x: 0, y: 0)
        case .topMiddle: TablePoint(x: 80, y: 0)
        case .topRight: TablePoint(x: 160, y: 0)
        case .bottomLeft: TablePoint(x: 0, y: 80)
        case .bottomMiddle: TablePoint(x: 80, y: 80)
        case .bottomRight: TablePoint(x: 160, y: 80)
        case .shortRail: TablePoint(x: 0, y: 40)
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var number: Int
    var level: String = "Подготовительный уровень"
    var title: String
    var details: [String]
    /// Метрика, в которую идёт результат упражнения.
    var metric: MetricKey
    /// Позиции битка (точки, куда клеить наклейку). Несколько — упражнение «с разных точек».
    var cueBalls: [TablePoint]
    /// Прицельные шары (например, «мост через шар»).
    var objectBalls: [TablePoint] = []
    /// Куда забивать (по одной лузе на каждую позицию битка; последняя повторяется).
    var targets: [Pocket]
    var attempts = 10
    /// Отработка винтов: на схеме — «часы» биткового шара.
    var spin = false
    /// Пирамида из 15 шаров.
    var rack = false
    /// Загружено тренером из PDF.
    var importedBy: UserID? = nil
    /// Удар по прицельному шару: «чужой» (забить прицельный) или «свояк» (забить биток от прицельного).
    var shot: ShotKind? = nil

    func target(for index: Int) -> Pocket? {
        targets.isEmpty ? nil : targets[min(index, targets.count - 1)]
    }

    /// Куда направлен удар: луза или (для «короткого борта») точка борта напротив битка.
    func targetPoint(for index: Int) -> TablePoint? {
        guard let target = target(for: index) else { return nil }
        if target == .shortRail, index < cueBalls.count { return TablePoint(x: 0, y: cueBalls[index].y) }
        return target.point
    }

    /// Все точки, на которые нужно поставить шары (для наклеек и камеры).
    var markPoints: [TablePoint] {
        if rack { return Self.rackPoints(apex: TablePoint(x: 45, y: 40)) + cueBalls }
        return cueBalls + objectBalls
    }

    /// Где поставить штатив: за лузой на продолжении линии удара, лицом к ученику (противоположный борт).
    var tripod: (point: TablePoint, hint: String) {
        let cue = cueBalls.first ?? TablePoint(x: 80, y: 40)
        let target = targetPoint(for: 0) ?? TablePoint(x: 160 - cue.x, y: cue.y < 40 ? 80 : 0)
        let dx = target.x - cue.x, dy = target.y - cue.y
        let length = max(1, hypot(dx, dy))
        // Точка за бортом на продолжении линии удара (≈ 50 см за столом)
        let point = TablePoint(x: min(175, max(-15, target.x + dx / length * 15)), y: min(95, max(-15, target.y + dy / length * 15)))
        let side: String
        if target.x <= 0.1 { side = "у левого короткого борта, напротив отметки \(Int(target.y))" }
        else if target.x >= 159.9 { side = "у правого короткого борта, напротив отметки \(Int(target.y))" }
        else if target.y <= 0.1 { side = "у верхнего длинного борта, напротив отметки \(Int(target.x))" }
        else { side = "у нижнего длинного борта, напротив отметки \(Int(target.x))" }
        let corner = (target.x <= 0.1 || target.x >= 159.9) && (target.y <= 0.1 || target.y >= 79.9)
        return (point, "Штатив: \(corner ? "за угловой лузой, " : "")\(side), в 30–50 см от стола, камера чуть выше борта и смотрит на вас вдоль линии удара — так видно, как шар идёт в лузу.")
    }

    static func rackPoints(apex: TablePoint) -> [TablePoint] {
        let d = 4.6   // шаг шаров в пирамиде в единицах сетки схемы
        var points: [TablePoint] = []
        for row in 0..<5 {
            for column in 0...row {
                points.append(TablePoint(x: apex.x - Double(row) * d * 0.866,
                                         y: apex.y - Double(row) * d / 2 + Double(column) * d))
            }
        }
        return points
    }
}

enum ShotKind: String, Codable, CaseIterable, Sendable {
    case objectBall, ownBall
    var title: String { self == .objectBall ? "Чужой шар" : "Свояк" }
    var metric: MetricKey { self == .objectBall ? .objectBall : .ownBall }
}

/// Как бить: мнимый шар (где окажется биток в момент удара), срез и толщина.
struct AimSolution {
    let ghost: TablePoint
    let object: TablePoint
    let pocket: TablePoint
    let cue: TablePoint
    /// Угол среза в градусах (0 — «в лоб»).
    let cutDegrees: Int
    let kind: ShotKind

    /// Толщина в терминах «долей шара» (перекрытие 1 − sin среза).
    var thickness: String {
        switch cutDegrees {
        case ..<8: "полный шар (в лоб)"
        case 8..<22: "≈ ¾ шара"
        case 22..<38: "≈ ½ шара"
        case 38..<55: "≈ ¼ шара"
        case 55..<75: "тонко (≈ ⅛ шара)"
        default: "очень тонко — удар на грани"
        }
    }

    var advice: [String] {
        switch kind {
        case .objectBall:
            [
                "Прицельтесь не в сам шар, а в центр мнимого шара (пунктир) — туда должен прийти центр битка.",
                "Срез \(cutDegrees)° — это \(thickness). Линия «мнимый шар → чужой шар» смотрит точно в лузу.",
                cutDegrees > 45 ? "Тонкий срез: добавьте силы и держите кий ровно — малейший увод даст промах." : "Бейте по центру битка средним ударом, кий проводите прямо по линии прицела.",
            ]
        case .ownBall:
            [
                "Свояк: после касания биток уходит под 90° к линии «мнимый шар → чужой шар» — по пунктиру в лузу.",
                "Прицел — центр мнимого шара, срез \(cutDegrees)° (\(thickness)).",
                "Бейте в центр битка, без верхнего и нижнего винта, средней силой: тогда угол ухода — ровно 90°. Верхний винт «закатит» биток ближе к чужому шару, нижний — оттянет назад.",
            ]
        }
    }
}

extension Exercise {
    /// Диаметр шара в единицах схемы (как на рисунке).
    static let ballDiameter = 4.6

    var aim: AimSolution? {
        guard let shot, let cue = cueBalls.first, let object = objectBalls.first, let target = target(for: 0) else { return nil }
        let pocket = target == .shortRail ? TablePoint(x: 0, y: object.y) : target.point
        let d = Self.ballDiameter
        let dx = pocket.x - object.x, dy = pocket.y - object.y
        let length = hypot(dx, dy)
        guard length > d + 0.5 else { return nil }
        let ux = dx / length, uy = dy / length
        let ghost: TablePoint
        switch shot {
        case .objectBall:
            ghost = TablePoint(x: object.x - ux * d, y: object.y - uy * d)
        case .ownBall:
            // Прямой угол в мнимом шаре: |OG| = d, OG ⟂ GP → угол при O: cos = d / |OP|
            let theta = acos(d / length)
            let candidates = [theta, -theta].map { angle -> TablePoint in
                let rx = ux * cos(angle) - uy * sin(angle), ry = ux * sin(angle) + uy * cos(angle)
                return TablePoint(x: object.x + rx * d, y: object.y + ry * d)
            }
            // Выбираем, куда биток реально может прийти и уйти в лузу
            ghost = candidates.max { a, b in Self.ownScore(cue: cue, ghost: a, object: object, pocket: pocket)
                < Self.ownScore(cue: cue, ghost: b, object: object, pocket: pocket) } ?? candidates[0]
        }
        // Срез: угол между направлением битка и линией центров
        let vx = ghost.x - cue.x, vy = ghost.y - cue.y
        let nx = object.x - ghost.x, ny = object.y - ghost.y
        let cosine = (vx * nx + vy * ny) / max(0.001, hypot(vx, vy) * hypot(nx, ny))
        let cut = Int((acos(min(1, max(-1, cosine))) * 180 / .pi).rounded())
        return AimSolution(ghost: ghost, object: object, pocket: pocket, cue: cue, cutDegrees: cut, kind: shot)
    }

    private static func ownScore(cue: TablePoint, ghost: TablePoint, object: TablePoint, pocket: TablePoint) -> Double {
        let vx = ghost.x - cue.x, vy = ghost.y - cue.y
        let v = max(0.001, hypot(vx, vy))
        let nx = (object.x - ghost.x) / ballDiameter, ny = (object.y - ghost.y) / ballDiameter
        let along = (vx * nx + vy * ny) / v
        guard along > 0.05 else { return -10 }   // биток не попадёт в шар
        let tx = vx / v - along * nx, ty = vy / v - along * ny
        let px = pocket.x - ghost.x, py = pocket.y - ghost.y
        return (tx * px + ty * py) / max(0.001, hypot(tx, ty) * hypot(px, py))
    }

    /// Примеры тренера: «чужой» и «свояк» — чтобы было видно, как работает подсказка.
    static let shotSamples: [Exercise] = [
        Exercise(id: "shot-1", number: 17, level: "Чужой шар и свояк", title: "Чужой шар в правый верхний угол",
                 details: ["Биток 40:40, чужой шар 120:22.", "Забить чужой шар в правую верхнюю лузу. 10 ударов."],
                 metric: .objectBall, cueBalls: [TablePoint(x: 40, y: 40)], objectBalls: [TablePoint(x: 120, y: 22)],
                 targets: [.topRight], shot: .objectBall),
        Exercise(id: "shot-2", number: 18, level: "Чужой шар и свояк", title: "Свояк в середину",
                 details: ["Биток 50:55, чужой шар 85:20.", "Сыграть свояка: биток от чужого шара уходит в верхнюю среднюю лузу. 10 ударов."],
                 metric: .ownBall, cueBalls: [TablePoint(x: 50, y: 55)], objectBalls: [TablePoint(x: 85, y: 20)],
                 targets: [.topMiddle], shot: .ownBall),
    ]
}

/// Результат упражнения на тренировке: забито `made` из `attempts`.
struct ExerciseResult: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let studentId: UserID
    let coachId: UserID
    let exerciseId: String
    let made: Int
    let attempts: Int
    var date = Date()

    var percent: Int { attempts == 0 ? 0 : Int((Double(made) / Double(attempts) * 100).rounded()) }
}

extension Exercise {
    private static func p(_ x: Double, _ y: Double) -> TablePoint { TablePoint(x: x, y: y) }

    /// «Подготовительный уровень» — 16 упражнений из методички тренера.
    static let preparatory: [Exercise] = [
        Exercise(id: "prep-1", number: 1, title: "Забить биток в середину с точки",
                 details: ["Биток 70:40. Винт 0.", "а) Сделать 10 ударов. Записать количество забитых шаров.",
                           "б) Сделать 10 ударов, только после первой паузы закрыть глаза (чтобы научиться видеть руку)."],
                 metric: .aiming, cueBalls: [p(70, 40)], targets: [.topMiddle]),
        Exercise(id: "prep-2", number: 2, title: "Забить биток в угол",
                 details: ["Биток 50:50. Винт 0."],
                 metric: .positionPlay, cueBalls: [p(50, 50)], targets: [.topLeft]),
        // «По линии N» — линия от отметки N нижнего борта к лузе; шар стоит на пересечении с горизонталью.
        Exercise(id: "prep-3", number: 3, title: "Забить биток в середину с разных точек",
                 details: ["Биток по линиям 60, 50, 40, 100, 110, 120 (на горизонтали 40)."],
                 metric: .aiming, cueBalls: [p(70, 40), p(65, 40), p(60, 40), p(90, 40), p(95, 40), p(100, 40)],
                 targets: [.topMiddle]),
        Exercise(id: "prep-4", number: 4, title: "Забить биток в угол с разных точек",
                 details: ["Биток по линиям 50, 60, 70 — в левый угол; 90, 100, 110 — в правый (на горизонтали 50)."],
                 metric: .positionPlay, cueBalls: [p(31, 50), p(37.5, 50), p(44, 50), p(116, 50), p(122.5, 50), p(129, 50)],
                 targets: [.topLeft, .topLeft, .topLeft, .topRight, .topRight, .topRight]),
        Exercise(id: "prep-5", number: 5, title: "Забить биток в угол с разных точек (дальние)",
                 details: ["Биток по линиям 80, 100, 120 (на горизонтали 55)."],
                 metric: .positionPlay, cueBalls: [p(55, 55), p(69, 55), p(82.5, 55)], targets: [.topLeft]),
        Exercise(id: "prep-6", number: 6, title: "Забить биток в угол: мост с борта",
                 details: ["Отработать мост с борта, когда биток находится на горизонтальной линии 65 с различных точек.",
                           "Биток по линиям 60, 50, 40 — в левый угол; 120, 110, 100 — в правый."],
                 metric: .stanceAndStroke, cueBalls: [p(48.75, 65), p(40.6, 65), p(32.5, 65), p(127.5, 65), p(119.4, 65), p(111.25, 65)],
                 targets: [.topLeft, .topLeft, .topLeft, .topRight, .topRight, .topRight]),
        Exercise(id: "prep-7", number: 7, title: "Забить биток в середину",
                 details: ["Биток 70:75. Винт 12. Глубина 2.", "Отработать стойку и мост к битку, стоящему близко к борту.",
                           "В этом случае тело необходимо расположить вдоль линии удара.",
                           "Правая нога чуть заступает за линию удара, ноги широко расставлены, опорная нога — левая (для правши), левая рука прямая, кий держим ближе к центру тяжести."],
                 metric: .stanceAndStroke, cueBalls: [p(70, 75)], targets: [.topMiddle], spin: true),
        Exercise(id: "prep-8", number: 8, title: "Забить биток в середину, мост через шар",
                 details: ["Биток 80:40. Шар 80:60.", "Как и в прошлом упражнении, стойка с разворотом тела вдоль линии удара.",
                           "Мост поднять максимально вверх."],
                 metric: .stanceAndStroke, cueBalls: [p(80, 40)], objectBalls: [p(80, 60)], targets: [.topMiddle]),
        Exercise(id: "prep-9", number: 9, title: "Забить биток в угол через середину стола",
                 details: ["Биток по линии 140.", "Биток по линии 0.", "Биток по линии 60 (короткого борта)."],
                 metric: .positionPlay, cueBalls: [p(120, 44), p(120, 60), p(103, 60)], targets: [.topLeft]),
        Exercise(id: "prep-10", number: 10, title: "Забить биток в угол через середину стола",
                 details: ["Биток 155:60."],
                 metric: .positionPlay, cueBalls: [p(155, 60)], targets: [.topLeft]),
        Exercise(id: "prep-11", number: 11, title: "Забить биток в угол с машинки",
                 details: ["Биток 20:60.", "Отработать правильное положение кисти в рабочей руке при ударе с машинкой."],
                 metric: .stanceAndStroke, cueBalls: [p(20, 60)], targets: [.topLeft]),
        Exercise(id: "prep-12", number: 12, title: "Возврат битка от короткого борта на кий",
                 details: ["Биток 120:40. Винт 0.", "Биток катится к дальнему короткому борту и возвращается точно на кий."],
                 metric: .cueBallControl, cueBalls: [p(120, 40)], targets: [.shortRail]),
        Exercise(id: "prep-13", number: 13, title: "Удар по битку с различной силой",
                 details: ["Биток 120:20.",
                           "Первый удар — докатить биток до короткого борта. Условно обозначить силу удара 0,75, так как с точки 120:20 до короткого борта биток проходит 3/4 стола.",
                           "Далее прибавляем по 1/4 стола: следующий удар по силе будет равен 1. И так далее до силы удара, равной 3.",
                           "Итого 10 ударов с различной силой: 0,75; 1; 1,25; 1,5; 1,75; 2; 2,25; 2,5; 2,75; 3."],
                 metric: .cueBallControl, cueBalls: [p(120, 20)], targets: [.shortRail]),
        Exercise(id: "prep-14", number: 14, title: "Забить биток в середину с различными винтами",
                 details: ["Биток 80:40.",
                           "Объяснить ученику 12-координатную систему винтов. Объяснить, как правильно ставить мост и выбирать направление удара при ударе с винтом.",
                           "Винт 1 Глубина 2", "Винт 2 Глубина 2", "Винт 3 Глубина 2 и 3", "Винт 4 Глубина 2", "Винт 5 Глубина 2", "Винт 6 Глубина 2", "Винт 7 Глубина 2", "Винт 8 Глубина 2", "Винт 9 Глубина 2 и 3", "Винт 10 Глубина 2", "Винт 11 Глубина 2", "Винт 12 Глубина 2"],
                 metric: .tacticalThinking, cueBalls: [p(80, 40)], targets: [.topMiddle], attempts: 12, spin: true),
        Exercise(id: "prep-15", number: 15, title: "Биток в угол с различными винтами",
                 details: ["Биток 50:50.", "Винт 1 Глубина 2", "Винт 2 Глубина 2", "Винт 3 Глубина 2 и 3", "Винт 4 Глубина 2", "Винт 5 Глубина 2", "Винт 6 Глубина 2", "Винт 7 Глубина 2", "Винт 8 Глубина 2", "Винт 9 Глубина 2 и 3", "Винт 10 Глубина 2", "Винт 11 Глубина 2", "Винт 12 Глубина 2"],
                 metric: .tacticalThinking, cueBalls: [p(50, 50)], targets: [.topLeft], attempts: 12, spin: true),
        Exercise(id: "prep-16", number: 16, title: "Разбить пирамиду и забить все шары",
                 details: ["Разбить пирамиду в первый шар и забить все шары по одному за 16 ударов.", "Пирамида — первый шар на отметке 45:40, биток 120:40."],
                 metric: .positionPlay, cueBalls: [p(120, 40)], targets: [], attempts: 16, rack: true),
    ]
}

// MARK: - Хранилище результатов

extension DemoBackend {
    var allExercises: [Exercise] { Exercise.preparatory + Exercise.shotSamples + customExercises }

    func exercise(_ id: String) -> Exercise? { allExercises.first { $0.id == id } }

    func results(of studentId: UserID, exercise: String? = nil) -> [ExerciseResult] {
        exerciseResults.filter { $0.studentId == studentId && (exercise == nil || $0.exerciseId == exercise) }
            .sorted { $0.date < $1.date }
    }

    /// Уровень по упражнению: средний процент трёх последних подходов.
    func level(of studentId: UserID, exercise: String) -> Int? {
        let last = results(of: studentId, exercise: exercise).suffix(3)
        guard !last.isEmpty else { return nil }
        return last.map(\.percent).reduce(0, +) / last.count
    }

    func addResults(_ items: [ExerciseResult]) {
        exerciseResults.append(contentsOf: items)
        save()
    }

    func saveImported(_ exercises: [Exercise]) {
        customExercises.removeAll { new in exercises.contains { $0.id == new.id } }
        customExercises.append(contentsOf: exercises)
        save()
    }

    /// Демо: история результатов для учеников, чтобы статистика и сравнение были не пустыми.
    func seedExerciseResults() {
        let coach = DemoBackend.alexeyId
        let plan: [(UserID, [String: [Int]])] = [
            (DemoBackend.ivanId, ["prep-1": [5, 6, 8], "prep-2": [4, 6, 7], "prep-3": [3, 5], "prep-7": [4, 5], "prep-12": [6, 7], "prep-14": [5, 7]]),
            (students[1].id, ["prep-1": [7, 8], "prep-2": [6, 7], "prep-4": [5], "prep-12": [8], "prep-15": [4]]),
            (DemoBackend.natashaId, ["prep-1": [4, 5], "prep-2": [3, 5], "prep-8": [6], "prep-13": [5, 6]]),
        ]
        var day = -30.0
        for (student, map) in plan {
            for (exerciseId, values) in map.sorted(by: { $0.key < $1.key }) {
                for (index, made) in values.enumerated() {
                    let attempts = exercise(exerciseId)?.attempts ?? 10
                    exerciseResults.append(ExerciseResult(studentId: student, coachId: coach, exerciseId: exerciseId,
                                                          made: min(made, attempts), attempts: attempts,
                                                          date: Date().addingTimeInterval((day + Double(index * 9)) * 86_400)))
                }
                day += 1
            }
        }
    }
}

// MARK: - Схема стола

/// Стол 160×80 как в методичке: цифры на бортах, пунктир от битка до бортов, стрелка удара, «часы» винта.
struct TableSchemeView: View {
    let exercise: Exercise
    var highlight: Int? = nil
    /// Подписи координат на бортах (в маленьких превью выключены).
    var labels = true
    /// Показать, где поставить штатив для съёмки.
    var showTripod = false
    /// «Чужой»/«свояк»: показать мнимый шар и линии прицела (Pro и тренер).
    var showAim = false

    /// Поле стола (внутри бортов) для размера холста — общая формула для рисования и нажатий.
    static func field(in size: CGSize, labels: Bool) -> CGRect {
        let margin = labels ? size.width * 0.05 : 0
        let tableRect = CGRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2)
        let rail = tableRect.width * 0.035
        return tableRect.insetBy(dx: rail, dy: rail)
    }

    /// Точка стола по нажатию (nil — мимо поля).
    static func point(at location: CGPoint, in size: CGSize, labels: Bool) -> TablePoint? {
        let field = field(in: size, labels: labels)
        let x = ((location.x - field.minX) / field.width * 160).rounded()
        let y = ((location.y - field.minY) / field.height * 80).rounded()
        guard (-3...163).contains(x), (-3...83).contains(y) else { return nil }
        return TablePoint(x: min(160, max(0, x)), y: min(80, max(0, y)))
    }

    var body: some View {
        Canvas { context, size in
            let margin = labels ? size.width * 0.05 : 0
            let tableRect = CGRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2)
            let rail = tableRect.width * 0.035
            let field = tableRect.insetBy(dx: rail, dy: rail)
            func map(_ p: TablePoint) -> CGPoint {
                CGPoint(x: field.minX + p.x / 160 * field.width, y: field.minY + p.y / 80 * field.height)
            }
            let ball = field.width / 160 * 4.6
            context.fill(Path(roundedRect: tableRect, cornerRadius: rail), with: .color(Color(red: 0.52, green: 0.33, blue: 0.05)))
            context.fill(Path(field), with: .color(Color(red: 0.36, green: 0.60, blue: 0.07)))
            context.stroke(Path(field.insetBy(dx: rail * 0.35, dy: rail * 0.35)), with: .color(.black.opacity(0.25)), lineWidth: 0.6)
            // Ромбики и цифры каждые 10
            for i in stride(from: 10, to: 160, by: 10) where i != 80 {
                let x = field.minX + Double(i) / 160 * field.width
                for y in [tableRect.minY + rail / 2, tableRect.maxY - rail / 2] {
                    var d = Path()
                    d.move(to: CGPoint(x: x, y: y - 2)); d.addLine(to: CGPoint(x: x + 1.6, y: y))
                    d.addLine(to: CGPoint(x: x, y: y + 2)); d.addLine(to: CGPoint(x: x - 1.6, y: y)); d.closeSubpath()
                    context.fill(d, with: .color(.white))
                }
                if labels {
                    context.draw(Text("\(i)").font(.system(size: max(6, size.width / 70), weight: .bold)),
                                 at: CGPoint(x: x, y: margin / 2))
                    context.draw(Text("\(i)").font(.system(size: max(6, size.width / 70), weight: .bold)),
                                 at: CGPoint(x: x, y: size.height - margin / 2))
                }
            }
            for i in stride(from: 10, to: 80, by: 10) {
                let y = field.minY + Double(i) / 80 * field.height
                for x in [tableRect.minX + rail / 2, tableRect.maxX - rail / 2] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(.white))
                }
                if labels {
                    context.draw(Text("\(i)").font(.system(size: max(6, size.width / 70), weight: .bold)), at: CGPoint(x: margin / 2, y: y))
                    context.draw(Text("\(i)").font(.system(size: max(6, size.width / 70), weight: .bold)),
                                 at: CGPoint(x: size.width - margin / 2, y: y))
                }
            }
            // Лузы с жёлтыми «губками»
            for pocket in [Pocket.topLeft, Pocket.topMiddle, Pocket.topRight, Pocket.bottomLeft, Pocket.bottomMiddle, Pocket.bottomRight] {
                let c = map(pocket.point)
                let r = ball * 0.8
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 1.5, width: (r + 1.5) * 2, height: (r + 1.5) * 2)),
                               with: .color(Color(red: 0.98, green: 0.82, blue: 0.10)), lineWidth: 1.5)
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            }
            // «Часы» винта
            if exercise.spin || exercise.details.joined().lowercased().contains("винт") {
                let center = CGPoint(x: field.minX + field.width * 0.78, y: field.midY - field.height * 0.08)
                let radius = field.height * 0.24
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.white))
                for ring in [0.33, 0.66, 1.0] {
                    let r = radius * ring
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                   with: .color(.black.opacity(0.7)), lineWidth: 0.5)
                }
                for hour in 0..<12 {
                    let angle = Double(hour) / 12 * 2 * .pi - .pi / 2
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                    context.stroke(line, with: .color(.black.opacity(0.6)), lineWidth: 0.4)
                    if labels {
                        context.draw(Text("\(hour == 0 ? 12 : hour)").font(.system(size: max(5, size.width / 90), weight: .bold)),
                                     at: CGPoint(x: center.x + cos(angle) * radius * 1.18, y: center.y + sin(angle) * radius * 1.18))
                    }
                }
                let dot = radius * 0.2
                context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)), with: .color(.red))
            }
            // Пунктир от битка до бортов (координаты)
            if labels, let first = exercise.cueBalls.first, exercise.cueBalls.count == 1 {
                let c = map(first)
                var guide = Path()
                guide.move(to: CGPoint(x: field.minX, y: c.y)); guide.addLine(to: c)
                guide.move(to: c); guide.addLine(to: CGPoint(x: c.x, y: field.maxY))
                context.stroke(guide, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
            }
            // Линии удара со стрелкой
            for (index, cue) in exercise.cueBalls.enumerated() where exercise.shot == nil {
                guard let targetPoint = exercise.targetPoint(for: index) else { continue }
                let from = map(cue), to = map(targetPoint)
                let active = highlight == nil || highlight == index
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(.black.opacity(active ? 0.85 : 0.25)), lineWidth: 1)
                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                let angle = atan2(to.y - from.y, to.x - from.x)
                var arrow = Path()
                arrow.move(to: CGPoint(x: mid.x + cos(angle) * 4, y: mid.y + sin(angle) * 4))
                arrow.addLine(to: CGPoint(x: mid.x + cos(angle + 2.6) * 4, y: mid.y + sin(angle + 2.6) * 4))
                arrow.addLine(to: CGPoint(x: mid.x + cos(angle - 2.6) * 4, y: mid.y + sin(angle - 2.6) * 4))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(.black.opacity(active ? 0.85 : 0.25)))
            }
            if exercise.rack {
                for point in Exercise.rackPoints(apex: TablePoint(x: 45, y: 40)) {
                    let c = map(point)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - ball / 2, y: c.y - ball / 2, width: ball, height: ball)),
                                 with: .color(Color(red: 0.98, green: 0.95, blue: 0.86)))
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - ball / 2, y: c.y - ball / 2, width: ball, height: ball)),
                                   with: .color(.black.opacity(0.4)), lineWidth: 0.5)
                }
            }
            for object in exercise.objectBalls {
                let c = map(object)
                context.fill(Path(ellipseIn: CGRect(x: c.x - ball / 2, y: c.y - ball / 2, width: ball, height: ball)),
                             with: .color(Color(red: 0.93, green: 0.72, blue: 0.20)))
            }
            if exercise.shot != nil {
                // Луза, куда играем, — красное кольцо
                if let target = exercise.targetPoint(for: 0) {
                    let c = map(target)
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - ball, y: c.y - ball, width: ball * 2, height: ball * 2)),
                                   with: .color(.red), lineWidth: 1.6)
                }
                if showAim, let aim = exercise.aim {
                    let cue = map(aim.cue), ghost = map(aim.ghost), object = map(aim.object), pocket = map(aim.pocket)
                    var cueLine = Path()
                    cueLine.move(to: cue); cueLine.addLine(to: ghost)
                    context.stroke(cueLine, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    context.stroke(Path(ellipseIn: CGRect(x: ghost.x - ball / 2, y: ghost.y - ball / 2, width: ball, height: ball)),
                                   with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    if aim.kind == .objectBall {
                        var objectLine = Path()
                        objectLine.move(to: object); objectLine.addLine(to: pocket)
                        context.stroke(objectLine, with: .color(Color(red: 0.98, green: 0.82, blue: 0.10)), lineWidth: 1.4)
                    } else {
                        var cueAfter = Path()
                        cueAfter.move(to: ghost); cueAfter.addLine(to: pocket)
                        context.stroke(cueAfter, with: .color(.white), style: StrokeStyle(lineWidth: 1.4))
                        let dx = object.x - ghost.x, dy = object.y - ghost.y
                        let len = max(0.001, hypot(dx, dy))
                        var objectLine = Path()
                        objectLine.move(to: object)
                        objectLine.addLine(to: CGPoint(x: object.x + dx / len * ball * 4, y: object.y + dy / len * ball * 4))
                        context.stroke(objectLine, with: .color(Color(red: 0.98, green: 0.82, blue: 0.10)),
                                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    }
                    if labels {
                        context.draw(Text("мнимый").font(.system(size: max(6, size.width / 60), weight: .semibold)).foregroundStyle(.white),
                                     at: CGPoint(x: ghost.x, y: ghost.y - ball * 1.3))
                    }
                }
            }
            if showTripod {
                let t = exercise.tripod.point
                let c = CGPoint(x: min(size.width - 8, max(8, field.minX + t.x / 160 * field.width)),
                                y: min(size.height - 8, max(8, field.minY + t.y / 80 * field.height)))
                context.draw(Text("📷").font(.system(size: max(10, size.width / 28))), at: c)
            }
            for (index, cue) in exercise.cueBalls.enumerated() {
                let c = map(cue)
                let active = highlight == nil || highlight == index
                let rect = CGRect(x: c.x - ball / 2, y: c.y - ball / 2, width: ball, height: ball)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(active ? 1 : 0.5)))
                context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 0.6)
            }
        }
        .aspectRatio(labels ? 1.95 : 2.1, contentMode: .fit)
        .background(labels ? Color.white : Color.clear)
        .accessibilityLabel("Схема: \(exercise.title)")
    }
}

/// Строка упражнения с уровнем ученика.
struct ExerciseRow: View {
    @Environment(\.palette) private var palette
    let exercise: Exercise
    let level: Int?
    var stars = 0

    var body: some View {
        HStack(spacing: Space.m) {
            TableSchemeView(exercise: exercise, labels: false).frame(width: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text("№\(exercise.number) · \(exercise.metric.title)").font(.caption).foregroundStyle(palette.textSecondary)
                Text(exercise.title).font(.callout.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(level.map { "\($0)%" } ?? "—").font(.headline.monospacedDigit())
                    .foregroundStyle(level == nil ? palette.textSecondary : palette.accent)
                if stars > 0 {
                    Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars))
                        .font(.caption).foregroundStyle(.yellow)
                }
            }
        }
        .padding(Space.s)
        .glassCard()
    }
}

// MARK: - Экраны

/// Список упражнений ученика (или тренера — для просмотра ученика).
struct ExercisesListView: View {
    let container: AppContainer
    let studentId: UserID

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s) {
                let groups = Dictionary(grouping: container.backend.allExercises, by: \.level)
                ForEach(groups.keys.sorted(), id: \.self) { level in
                    Text(level).font(.headline).padding(.top, Space.s)
                    ForEach(groups[level]?.sorted { $0.number < $1.number } ?? []) { exercise in
                        NavigationLink {
                            ExerciseDetailView(container: container, exercise: exercise, studentId: studentId)
                        } label: {
                            ExerciseRow(exercise: exercise, level: container.backend.level(of: studentId, exercise: exercise.id),
                                        stars: container.backend.stars(of: studentId, exercise: exercise.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Упражнения")
    }
}

struct ExerciseDetailView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let exercise: Exercise
    let studentId: UserID
    @State private var showTrainer = false
    @State private var showPaywall = false
    @State private var showEditor = false
    @State private var showProPaywall = false

    private var isPro: Bool { container.role == .trainer || container.backend.hasSubscription(container.currentUserId) }

    /// «Как бить» для чужого шара и свояка: мнимый шар, срез, советы (Pro).
    @ViewBuilder
    private var aimCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Как бить: \(exercise.shot?.title.lowercased() ?? "")", systemImage: "scope").font(.headline)
            if isPro, let aim = exercise.aim {
                TableSchemeView(exercise: exercise, showAim: true)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                HStack(spacing: Space.m) {
                    Label("Срез \(aim.cutDegrees)°", systemImage: "angle")
                    Label(aim.thickness, systemImage: "circle.lefthalf.filled")
                }
                .font(.caption.weight(.semibold))
                ForEach(aim.advice, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle").font(.callout)
                }
                Text("Пунктирный круг — мнимый шар: в этой точке должен оказаться центр битка в момент удара.")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            } else {
                Text("В Pro приложение рисует мнимый шар, показывает срез и толщину и объясняет, как сыграть \(exercise.shot == .ownBall ? "свояка" : "чужой шар").")
                    .font(.callout).foregroundStyle(palette.textSecondary)
                Button { showProPaywall = true } label: { Label("Открыть в Pro", systemImage: "lock.open") }
                    .buttonStyle(.cueSecondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Видео-урок тренера: ученик с Pro смотрит, тренер добавляет.
    @ViewBuilder
    private var lessonCard: some View {
        let file = container.backend.exerciseLessons[exercise.id]
        if container.role == .trainer {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Видео-урок", systemImage: "play.rectangle").font(.headline)
                LessonVideoPicker(container: container, exerciseId: exercise.id)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        } else if let file {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Видео-урок тренера", systemImage: "play.rectangle").font(.headline)
                if isPro {
                    VideoPlayer(player: AVPlayer(url: DemoBackend.videoURL(file)))
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                    Text("Тренер рассказывает, как выполнять упражнение и на что обратить внимание.")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                } else {
                    Text("Тренер записал видео: как выполнять упражнение и на что обратить внимание. Доступно в Pro.")
                        .font(.callout).foregroundStyle(palette.textSecondary)
                    Button { showProPaywall = true } label: { Label("Смотреть в Pro", systemImage: "lock.open") }
                        .buttonStyle(.cueSecondary)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    var body: some View {
        let results = container.backend.results(of: studentId, exercise: exercise.id)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Упражнение №\(exercise.number)").font(.caption).foregroundStyle(palette.textSecondary)
                Text(exercise.title).font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                TableSchemeView(exercise: exercise, showTripod: true)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(exercise.details, id: \.self) { Text($0).font(.callout) }
                    Label("Точки для шаров: " + exercise.markPoints.prefix(6).map { "\(Int($0.x)):\(Int($0.y))" }.joined(separator: ", ")
                          + (exercise.markPoints.count > 6 ? "…" : ""), systemImage: "smallcircle.filled.circle")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    Label("\(exercise.attempts) ударов · метрика «\(exercise.metric.title)»", systemImage: "target")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    Label(exercise.tripod.hint, systemImage: "camera.on.rectangle")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if exercise.shot != nil { aimCard }
                lessonCard

                if container.role == .student && studentId == container.currentUserId {
                    Button {
                        if container.backend.hasSubscription(container.currentUserId) { showTrainer = true } else { showPaywall = true }
                    } label: {
                        Label("Расставить шары с камерой", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.cueGlassProminent)
                }

                let videos = container.backend.videos(of: studentId, exercise: exercise.id)
                if !videos.isEmpty {
                    Text("Видео выполнения").font(.headline)
                    ForEach(videos) { video in
                        VideoPlayer(player: AVPlayer(url: DemoBackend.videoURL(video.file)))
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                        Text(Fmt.stamp(video.date)).font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }

                Text("Результаты").font(.headline)
                if results.isEmpty {
                    Text("Ещё не выполнялось — тренер отметит результат после тренировки").foregroundStyle(palette.textSecondary)
                } else {
                    Chart(results) { result in
                        LineMark(x: .value("Дата", result.date), y: .value("%", result.percent))
                            .foregroundStyle(palette.accent)
                        PointMark(x: .value("Дата", result.date), y: .value("%", result.percent))
                            .foregroundStyle(palette.accent)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 160)
                    .padding(Space.m)
                    .glassCard()
                    ForEach(results.reversed()) { result in
                        HStack {
                            Text(Fmt.shortDay(result.date))
                            Spacer()
                            Text("\(result.made) из \(result.attempts)").monospacedDigit()
                            Text("\(result.percent)%").bold().monospacedDigit().foregroundStyle(palette.accent)
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("№\(exercise.number)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showTrainer) { TableCameraTrainer(container: container, exercise: exercise) }
        .sheet(isPresented: $showEditor) {
            ExerciseEditor(exercise: exercise, container: container) { container.backend.saveImported([$0]) }
        }
        .toolbar {
            if container.role == .trainer && exercise.importedBy == container.currentUserId {
                Button("Изменить") { showEditor = true }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(container: container) { showTrainer = true } }
        .sheet(isPresented: $showProPaywall) { PaywallView(container: container) }
    }
}

/// Результаты упражнений в оценке тренировки: «забито X из N».
struct ExerciseResultsEditor: View {
    @Environment(\.palette) private var palette
    let exercises: [Exercise]
    @Binding var made: [String: Int]

    var body: some View {
        ForEach(exercises) { exercise in
            let included = made[exercise.id] != nil
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(get: { included }, set: { made[exercise.id] = $0 ? exercise.attempts / 2 : nil })) {
                    Text("№\(exercise.number) \(exercise.title)").font(.callout)
                }
                if let value = made[exercise.id] {
                    Stepper("Забито \(value) из \(exercise.attempts)", value: Binding(get: { value }, set: { made[exercise.id] = $0 }),
                            in: 0...exercise.attempts)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }
}

/// Статистика ученика для тренера и сравнение с другим учеником.
struct StudentStatsView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let studentId: UserID
    @State private var compareWith: UserID?

    private var backend: DemoBackend { container.backend }

    var body: some View {
        let others = backend.students.filter { $0.id != studentId }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Picker("Сравнить с", selection: $compareWith) {
                    Text("Без сравнения").tag(UserID?.none)
                    ForEach(others) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .padding(Space.s)
                .glassCard()

                legend
                Text("Навыки").font(.headline)
                VStack(spacing: Space.s) {
                    ForEach(MetricKey.allCases) { key in
                        comparisonRow(key.title, backend.progress(for: studentId).current[key],
                                      compareWith.flatMap { backend.progress(for: $0).current[key] })
                    }
                }
                .padding(Space.m)
                .glassCard()

                Text("Упражнения, % попаданий").font(.headline)
                VStack(spacing: Space.s) {
                    ForEach(backend.allExercises) { exercise in
                        let mine = backend.level(of: studentId, exercise: exercise.id)
                        let other = compareWith.flatMap { backend.level(of: $0, exercise: exercise.id) }
                        if mine != nil || other != nil {
                            comparisonRow("№\(exercise.number) \(exercise.title)", mine, other)
                        }
                    }
                }
                .padding(Space.m)
                .glassCard()
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: Space.l) {
            Label(backend.name(studentId), systemImage: "circle.fill").foregroundStyle(palette.accent)
            if let compareWith {
                Label(backend.name(compareWith), systemImage: "circle.fill").foregroundStyle(palette.accentSecondary)
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func comparisonRow(_ title: String, _ mine: Int?, _ other: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).lineLimit(1)
                Spacer()
                Text(mine.map(String.init) ?? "—").font(.caption.bold().monospacedDigit()).foregroundStyle(palette.accent)
                if compareWith != nil {
                    Text(other.map(String.init) ?? "—").font(.caption.bold().monospacedDigit()).foregroundStyle(palette.accentSecondary)
                }
            }
            bar(mine, palette.accent)
            if compareWith != nil { bar(other, palette.accentSecondary) }
        }
    }

    private func bar(_ value: Int?, _ color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textSecondary.opacity(0.15))
                Capsule().fill(color).frame(width: geometry.size.width * Double(value ?? 0) / 100)
            }
        }
        .frame(height: 6)
    }
}
