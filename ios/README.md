# Биток — iOS

iOS 17+, SwiftUI, Observation (`@Observable`), Swift Testing. Требуется **Xcode 16+** (типизированные ошибки `throws(BookingError)`); Liquid Glass (`glassEffect`) включается автоматически при сборке в **Xcode 26+**, на более ранних SDK используется `.ultraThinMaterial`.

## Запуск

```bash
brew install xcodegen
cd ios
xcodegen generate
open Bitok.xcodeproj
```

Приложение запускается на **демо-данных** (`App/Sources/DemoData.swift`) — backend не нужен. В «Профиле» можно переключить оформление (Авто / Ivory & Oxblood / Midnight Chalk), флаг магазина и выйти из аккаунта.

### Тестовые учётки (демо-вход, без сервера)

| Роль | Имя | Телефон | Код из SMS |
|------|-----|---------|-----------|
| Тренер | Алексей Воронов | `+7 900 000-00-01` | `1234` |
| Ученик | Иван Петров | `+7 900 000-00-02` | `1234` |

На экране входа есть и кнопки быстрого входа под каждой учёткой. Сессия сохраняется между запусками.

## Установка на iPhone без Mac (Windows)

CI на GitHub собирает неподписанный установочный файл **`Bitok.ipa`** (задача «iOS IPA для установки»). Подписать и поставить его на iPhone можно с Windows бесплатным Apple ID:

1. Скачать `Bitok.ipa`: **GitHub → Actions → последний успешный запуск CI → Artifacts → Bitok-ipa** (распаковать zip).
2. Установить на ПК **iTunes** (версию с сайта Apple, не из Microsoft Store) и **Sideloadly** (sideloadly.io).
3. Подключить iPhone кабелем, на телефоне нажать «Доверять этому компьютеру».
4. В Sideloadly: перетащить `Bitok.ipa`, выбрать iPhone, ввести Apple ID → **Start**. Пароль Apple ID отправляется только в Apple; для безопасности лучше завести отдельный Apple ID для тестов.
5. На iPhone: **Настройки → Конфиденциальность и безопасность → Режим разработчика → Вкл.**, затем **Настройки → Основные → VPN и управление устройством → ваш Apple ID → Доверять**.

Ограничения бесплатного Apple ID: приложение работает 7 дней (потом повторить шаг 4), не более 3 таких приложений на устройстве.

## Установка на iPhone с Mac

1. Mac с **Xcode 16+** (для Liquid Glass — Xcode 26), бесплатный Apple ID.
2. `brew install xcodegen`, затем `cd ios && xcodegen generate && open Bitok.xcodeproj`.
3. Xcode → **Settings → Accounts** → добавить Apple ID.
4. Цель **Bitok → Signing & Capabilities** → **Team**: ваш Personal Team. Если Xcode пишет, что bundle ID занят, поменяйте его на уникальный, например `app.bitok.ios.ivan`.
5. Подключить iPhone кабелем, на телефоне: **Настройки → Конфиденциальность и безопасность → Режим разработчика → Вкл.** (перезагрузка).
6. Выбрать iPhone в списке устройств Xcode и нажать **Run** (⌘R).
7. При первом запуске: **Настройки → Основные → VPN и управление устройством** → доверять своему Apple ID.

С бесплатным Apple ID приложение работает 7 дней, затем его нужно снова установить из Xcode. Для раздачи тестировщикам через TestFlight нужен платный Apple Developer Program.

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
