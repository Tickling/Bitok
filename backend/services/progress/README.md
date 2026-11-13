# Progress Service

**Статус:** каркас, реализация — этап MVP-3 (ANALYTICS.md, раздел 9.3.1)
**Стек:** NestJS · **Контракт:** `api-contracts/openapi/progress.yaml` · **Описание:** ANALYTICS.md, раздел 4.2.3

## Ответственность

Оценки тренера по 5 метрикам (0–100), EMA, история изменений метрик, приватность прогресса (тренер видит всегда).

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
