# Payment Service — ЗАДЕЛ

**Статус:** каркас, реализация — этап v1.0 (ANALYTICS.md, раздел 9.3.1)
**Стек:** NestJS · **Контракт:** `api-contracts/openapi/payment.yaml` · **Описание:** ANALYTICS.md, раздел 4.2.7, 4.3.6

## Ответственность

Платёжные сессии СБП (QR / ссылка), webhooks банка с проверкой подписи и webhook_inbox, возвраты, фискализация 54-ФЗ. В MVP выключен флагом paymentsEnabled.

## Как реализовывать

Повторить структуру эталонного сервиса [`services/booking`](../booking):

```
src/
├── domain/          # агрегаты, политики, доменные ошибки — без зависимостей от NestJS и Kafka
├── application/     # обработчики команд и запросов, порты (интерфейсы)
├── infrastructure/  # адаптеры: PostgreSQL, Outbox, Kafka-консьюмеры, внешние API
└── api/             # контроллеры по OpenAPI-контракту, RFC 7807
```

Правила: своя БД (database-per-service), события только через Transactional Outbox, консьюмеры идемпотентны (`processed_events`).
