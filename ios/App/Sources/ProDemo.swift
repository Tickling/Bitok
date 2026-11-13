// App/Sources/ProDemo.swift — демо-экраны «Биток Про» для скриншотов «Помощи» и карусель с подсказками.
import SwiftUI
import CoreDomain
import DesignSystem

struct ProDemoScreen: View {
    let container: AppContainer
    let page: String

    var body: some View {
        let exercise = Exercise.preparatory[2]   // №3: несколько точек — видно расстановку
        switch page {
        case "proExercise":
            NavigationStack { ExerciseDetailView(container: container, exercise: Exercise.preparatory[0], studentId: container.currentUserId) }
        case "proPaywall":
            PaywallView(container: container)
        case "proResult":
            TrainingResultView(container: container, exercise: Exercise.preparatory[0],
                               result: TrainingResult(videoURL: nil, shots: [
                                   ShotEvent(time: 4, made: true, advice: "Отличный удар! 🔥"),
                                   ShotEvent(time: 11, made: false, advice: TableCameraModel.advice(start: TablePoint(x: 70, y: 40),
                                                                                                    target: TablePoint(x: 80, y: 0),
                                                                                                    end: TablePoint(x: 66, y: 4))),
                                   ShotEvent(time: 18, made: true, advice: "Чисто!"),
                                   ShotEvent(time: 25, made: true, advice: "Есть!"),
                                   ShotEvent(time: 31, made: false, advice: TableCameraModel.advice(start: TablePoint(x: 70, y: 40),
                                                                                                    target: TablePoint(x: 80, y: 0),
                                                                                                    end: TablePoint(x: 76, y: 22))),
                                   ShotEvent(time: 38, made: true, advice: "Есть!"), ShotEvent(time: 45, made: true, advice: "Есть!"),
                               ], attempts: 10)) {}
        default:
            TableCameraTrainer(container: container, exercise: exercise, demo: String(page.dropFirst(3)).lowercased())
        }
    }
}

/// Шаг карусели: скриншот с цифрами и подписи.
struct ProCarouselStep: Identifiable {
    let id = UUID()
    let image: String
    let title: String
    let items: [String]

    static let all: [ProCarouselStep] = [
        ProCarouselStep(image: "Help-pro-exercise", title: "1. Выберите упражнение",
                        items: ["Схема: где стоит биток, куда бить и «часы» винта", "📷 — где поставить штатив", "«Расставить шары с камерой» — начать"]),
        ProCarouselStep(image: "Help-pro-framing", title: "2. Весь стол в кадре",
                        items: ["Рамка зелёная — стол найден", "Подсказка: отойти назад или подойти ближе", "«Дальше» — к точкам для шаров"]),
        ProCarouselStep(image: "Help-pro-marks", title: "3. Наклейте точки",
                        items: ["Голубые круги — куда клеить точки", "Координаты точек по сетке стола", "«Наклеил(а)» — ставим шары"]),
        ProCarouselStep(image: "Help-pro-balls", title: "4. Проверка шаров",
                        items: ["Зелёный — шар на месте, красный — ошибка", "Подсказка, куда сдвинуть шар", "Когда всё зелёное — к выполнению"]),
        ProCarouselStep(image: "Help-pro-perform", title: "5. Выполнение на штативе",
                        items: ["Идёт запись, счёт ударов", "Похвала или совет после каждого удара", "Мотивация 💪 и «Завершить»"]),
        ProCarouselStep(image: "Help-pro-result", title: "6. Итог и разбор",
                        items: ["Звёзды за упражнение", "Момент ошибки на видео и совет", "Видео — в галерею, в приложение или тренеру"]),
    ]
}

/// Карусель скриншотов «Про» в «Помощи».
struct ProCarousel: View {
    @Environment(\.palette) private var palette
    @State private var zoomed: String?

    var body: some View {
        let steps = ProCarouselStep.all.filter { UIImage(named: $0.image) != nil }
        if !steps.isEmpty {
            TabView {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(step.title).font(.headline)
                        Image(step.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                            .frame(maxWidth: .infinity)
                            .onTapGesture { zoomed = step.image }
                        ForEach(Array(step.items.enumerated()), id: \.offset) { index, text in
                            HStack(alignment: .top, spacing: Space.s) {
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(palette.onAccent)
                                    .frame(width: 20, height: 20).background(palette.accent, in: Circle())
                                Text(text).font(.callout)
                            }
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, Space.s)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 620)
            .fullScreenCover(item: Binding(get: { zoomed.map(ZoomRef.init) }, set: { zoomed = $0?.id })) { ref in
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(ref.id).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { zoomed = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                    }
                    .padding()
                }
            }
        }
    }

    private struct ZoomRef: Identifiable { let id: String }
}
