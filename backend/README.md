# Биток — Backend

Монорепозиторий backend: контракты, shared-kernel и сервисы. Архитектура — [ANALYTICS.md](../ANALYTICS.md), разделы 4 и 9.

```
backend/
├── api-contracts/
│   ├── openapi/          # 7 OpenAPI 3.0 спецификаций (contract-first) — источник правды для API
│   └── events/           # JSON Schema доменных событий + конверт CloudEvents
├── shared-kernel/        # Money, Problem Details (RFC 7807), CloudEvents, Outbox — только инфраструктура
├── services/
│   ├── booking/          # ✅ Эталонный сервис (NestJS): state machine, PaymentPolicy, saga оплаты, тесты
│   ├── messaging/        # ✅ Go: дедупликация, тихие часы, напоминания, health
│   ├── identity/ progress/ achievement/ content/ bff/   # каркасы (README) — реализуются по образцу booking
│   └── payment/ shop/    # ЗАДЕЛ: каркасы, включаются флагами в v1.0
└── deploy/               # docker-compose, схема booking_db, инициализация БД
```

## Быстрый старт

```bash
cd backend
npm install
npm test          # тесты всех TS-сервисов
npm run build
```

```bash
cd backend/services/messaging
go test -race ./...
```

```bash
cd backend
docker compose -f deploy/docker-compose.yml up --build
```

Запуск Booking Service без Docker (in-memory хранилище и демо-слоты):

```bash
cd backend/services/booking
PORT=3001 node dist/main.js
```

```bash
curl -X POST localhost:3001/v1/bookings \
  -H 'Content-Type: application/json' -H 'x-user-id: ivan' \
  -H 'Idempotency-Key: 6f1e3a52-8c0d-4a7b-b1f2-9d3c4e5f6a7b' \
  -d '{"slotId":"demo-slot-2-0","comment":"Хочу поработать над выходом"}'
```

> `x-user-id` / `x-user-role` в проде проставляет API Gateway после проверки JWT.

## Что покрыто тестами в Booking Service

| Требование | Тест |
|------------|------|
| `paymentsEnabled = false`: `AWAITING_COACH_APPROVAL → CONFIRMED` | `State machine` |
| `paymentsEnabled = true`: `→ AWAITING_PAYMENT`, холд = дедлайн оплаты + grace | `State machine` |
| 100 параллельных броней одного слота → ровно одна успешна (AC-005.2) | `Конкурентность` |
| Idempotency-Key: повтор → та же бронь, другое тело → 422 | `Конкурентность и идемпотентность` |
| Повторный webhook оплаты обрабатывается один раз | `Saga оплаты` |
| Поздняя оплата после потери слота → `booking.payment_rejected` (возврат) | `Saga оплаты` |
| Гонка «истечь» vs «оплачено» → ровно один победитель | `Saga оплаты` |

## Подключение оплаты (v1.0)

Ядро бронирования не меняется (ADR-008): реализовать адаптер `PaymentGateway` и включить `FeatureFlagPaymentPolicy` с флагом `paymentsEnabled` из Unleash.
