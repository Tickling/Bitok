# Identity Service

**Статус:** каркас, реализация — этап MVP-1 (ANALYTICS.md, раздел 9.3.1)
**Стек:** NestJS · **Контракт:** `api-contracts/openapi/identity.yaml` · **Описание:** ANALYTICS.md, раздел 4.2.1

## Ответственность

Регистрация и вход по телефону/email (OTP), JWT + refresh-ротация, профили, роли, ContactAccessGrant (кто из тренеров видит телефон ученика).

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
