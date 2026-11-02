# Биток — iOS

iOS 17+, SwiftUI, Observation (`@Observable`), Swift Testing. Требуется **Xcode 16+** (типизированные ошибки `throws(BookingError)`); Liquid Glass (`glassEffect`) включается автоматически при сборке в **Xcode 26+**, на более ранних SDK используется `.ultraThinMaterial`.

## Запуск

```bash
brew install xcodegen
cd ios
xcodegen generate
open Bitok.xcodeproj
```

Приложение запускается на **демо-данных** (`App/Sources/DemoData.swift`) — backend не нужен. В «Профиле» можно переключить оформление (Авто / Ivory & Oxblood / Midnight Chalk), роль (ученик / тренер) и флаг магазина.

## Структура (ANALYTICS.md, раздел 4.5.2)

```
ios/
├── project.yml                 # XcodeGen
├── App/                        # Composition root: AppContainer (выбор адаптеров), RootTabView, демо-данные, иконка
└── Packages/
    ├── CoreDomain/             # ID<T>, Money, User/Trainer/Student, Payment + порт PaymentGateway, FeatureFlags
    ├── CoreNetwork/            # APIClient: Idempotency-Key, If-Match, RFC 7807, refresh-токен
    ├── CorePersistence/        # Офлайн-кэш снимков экранов
    ├── DesignSystem/           # Палитры, ThemeManager («Авто»), GlassCard, кнопки, StatusPill, RadarChart
    ├── IdentityKit/            # OTP (SMS / email), токены
    ├── BookingKit/             # BookingDomain (state machine, PaymentPolicy) + BookingUI (календари, EventKit, напоминания)
    ├── PaymentKit/             # ЗАДЕЛ: SBPPaymentView (QR, «Оплатить через СБП», таймер, статус)
    ├── ProgressKit/            # ProgressDomain (5 метрик 0–100, EMA, приватность) + ProgressUI (радар, история)
    ├── AchievementKit/         # AchievementDomain (турниры, медали, статистика) + AchievementUI (рамки, медали)
    ├── ChatKit/                # Сообщения, «Предложить поиграть», «Игроки клуба»
    ├── ContentKit/             # Новости и уроки
    └── ShopKit/                # ЗАДЕЛ: Product, Order, экран «Скоро»
```

**Правила зависимостей:** фичи не зависят друг от друга; `*Domain` — без SwiftUI; связывание — только в `App/Sources/AppContainer.swift`.

## Тесты

```bash
for p in CoreDomain CoreNetwork BookingKit ProgressKit AchievementKit ChatKit ShopKit; do
  swift test --package-path Packages/$p
done
```

## Подключение оплаты СБП (v1.0)

Заменить `NoopPaymentGateway()` в `AppContainer` на реальный адаптер к BFF. Экран `SBPPaymentView` появится сам, когда сервер вернёт бронь в статусе `AWAITING_PAYMENT` и `/bff/config` включит `paymentsUIEnabled`.
