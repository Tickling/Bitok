// App/Sources/HelpShots.swift — «Помощь» со скриншотами: цифры на картинке → подписи ниже.
// Скриншоты снимаются в CI (ios/scripts/screenshots.sh) с настоящего приложения.
import SwiftUI
import CoreDomain
import DesignSystem

struct HelpShot: Identifiable {
    let image: String
    let title: String
    let items: [String]
    var id: String { image }

    static let student: [HelpShot] = [
        HelpShot(image: "Help-student-calendar", title: "Запись на тренировку", items: ["Выберите тренера", "Дни со свободным временем активны — нажмите на день. Точка — ваша запись", "Выберите время и нажмите «Продолжить», затем «Записаться»", "Вкладка «Календарь»: ниже — групповые тренировки и «Мои записи»"]),
        HelpShot(image: "Help-student-chat", title: "Чат с тренером", items: ["Нажмите на имя — откроется профиль тренера", "Карточка записи: статус обновляется сам", "«Отменить» — отмена прямо из чата", "📅 — записаться к этому тренеру"]),
        HelpShot(image: "Help-student-players", title: "Игроки клуба", items: ["Раздел «Игроки» — другие ученики клуба", "Нажмите на игрока → «Написать». В чате «＋»: сыграть или обменяться номерами", "🔒 — игрок скрыл прогресс"]),
        HelpShot(image: "Help-student-shop", title: "Магазин и подарки", items: ["«Контент» → «Магазин»", "Категории: кии, мелки, перчатки, аксессуары, ремонт и обслуживание", "Нажмите на товар: «Купить в подарок» — выбор ученика, открытка и поздравление", "Услуги мастеров: ремонт и обслуживание кия"]),
        HelpShot(image: "Help-student-profile", title: "Профиль", items: ["Карточка игрока: рейтинг, уровень и 5 навыков", "Следующая тренировка — нажмите, чтобы открыть календарь", "Редактировать профиль: имя, город, фото с масштабом", "Настройки: тема, размер текста, уведомления, значок приложения"]),
        HelpShot(image: "Help-student-progress", title: "Прогресс", items: ["Общий рейтинг и уровень", "Радар 5 навыков: оценки тренера после каждой тренировки", "Достижения и динамика навыков"]),
    ]

    static let coach: [HelpShot] = [
        HelpShot(image: "Help-coach-day", title: "Расписание и заявки", items: ["Режимы: день, неделя, месяц", "Новая заявка: «Подтвердить» или «Отклонить». Нажмите на карточку — подробности", "«Предложить другое время» — ученику уйдёт ваш вариант", "Свободные слоты с названием места"]),
        HelpShot(image: "Help-coach-week", title: "Сетка недели", items: ["Вкладка «Неделя»", "Нажмите на день — откроется его список", "Цвет клетки — статус: подтверждена, заявка, прошла, группа, свободно. Выключается в настройках"]),
        HelpShot(image: "Help-coach-chat", title: "Чат с учеником", items: ["Карточка тренировки — нажмите для подробностей", "«Поменять» — поменять ученика местами с другим", "Сообщения ученика", "📅 — предложить ученику время"]),
        HelpShot(image: "Help-coach-venues", title: "Места и расписание", items: ["Место: адрес, дни и часы. Нажмите, чтобы изменить", "🔒 Место только для выбранных учеников", "Тест-зал 24/7 — слот каждый час, для проверки уведомлений", "Добавить новое место"]),
        HelpShot(image: "Help-coach-students", title: "Ученики и цены", items: ["Поиск по имени или телефону", "Нажмите на ученика: навыки, тренировки и своя цена для него", "Рейтинг ученика", "Ждёт оценки после тренировки"]),
        HelpShot(image: "Help-coach-profile", title: "Профиль тренера", items: ["Карточка: квалификация, места, часы и счётчики", "Места и расписание: где, когда и для кого", "Групповые (игровые) тренировки", "Настройки, значок приложения, помощь"]),
    ]
}

/// Скриншот с пронумерованными подписями.
struct HelpShotCard: View {
    @Environment(\.palette) private var palette
    let shot: HelpShot
    @State private var zoomed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(shot.title).font(.title3.weight(.semibold)).fontDesign(palette.headingDesign)
            Image(shot.image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(palette.glassStroke))
                .frame(maxWidth: .infinity)
                .onTapGesture { zoomed = true }
            ForEach(Array(shot.items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: Space.s) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(palette.onAccent)
                        .frame(width: 22, height: 22)
                        .background(palette.accent, in: Circle())
                    Text(text).font(.callout)
                }
            }
        }
        .padding(Space.m)
        .glassCard()
        .fullScreenCover(isPresented: $zoomed) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Image(shot.image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                Button { zoomed = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                }
                .padding()
            }
        }
    }
}
