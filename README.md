# 🎱 Биток (Bitok)

**Биток** — iOS-приложение для записи на тренировки по бильярду, отслеживания прогресса игрока и геймификации обучения, с микросервисным backend.

> Каждая тренировка начинается с битка.

## Документация

| Документ | Содержание |
|----------|------------|
| [ANALYTICS.md](ANALYTICS.md) | Единый аналитический документ: требования (FR/NFR), архитектура (C4, bounded contexts, события, Saga, Outbox), доменные модели, OpenAPI-контракты, sequence- и BPMN-диаграммы, дизайн-система, ADR, roadmap |
| [docs/design/](docs/design/) | Интерактивные макеты, по которым принимались дизайн-решения: стили, иконки, концепции K1–K4, чат и списки учеников |

## Структура репозитория

```
bitok/
├── ANALYTICS.md            # Аналитика и архитектура (источник правды)
├── docs/design/            # Макеты и дизайн-решения
├── ios/                    # iOS-клиент: Swift Packages по доменам
└── backend/                # Контракты, shared-kernel, сервисы, docker-compose
```

Подробности — в README каждого раздела: [ios/README.md](ios/README.md), [backend/README.md](backend/README.md).

## Ключевые решения

- **Платформа:** iOS 17+ (SwiftUI, Observation, Liquid Glass на iOS 26 с fallback).
- **Оформления:** Ivory & Oxblood (светлое) и Midnight Chalk (тёмное), по умолчанию «Авто».
- **Backend:** NestJS (TypeScript) для доменных сервисов и BFF, Go — для Messaging; Kafka, PostgreSQL (database-per-service), Redis.
- **Оплата СБП:** архитектурный задел (порты `PaymentPolicy` / `PaymentGateway`, флаг `paymentsEnabled`), в MVP выключена.
