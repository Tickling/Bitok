-- booking_db: ключевые инварианты (ANALYTICS.md, раздел 5.1).
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE booking_slot (
    id               UUID PRIMARY KEY,
    trainer_id       UUID        NOT NULL,
    club_id          UUID        NOT NULL,
    table_number     INT,
    starts_at        TIMESTAMPTZ NOT NULL,
    duration_minutes INT         NOT NULL CHECK (duration_minutes BETWEEN 30 AND 180 AND duration_minutes % 15 = 0),
    price_minor      BIGINT      NOT NULL CHECK (price_minor >= 0),
    status           TEXT        NOT NULL,
    held_until       TIMESTAMPTZ,
    version          INT         NOT NULL DEFAULT 0,
    -- Слоты тренера не пересекаются (BR-004.1)
    CONSTRAINT slot_no_overlap EXCLUDE USING gist (
        trainer_id WITH =,
        tstzrange(starts_at, starts_at + make_interval(mins => duration_minutes)) WITH &&
    ) WHERE (status <> 'CANCELLED')
);

CREATE TABLE booking (
    id                  UUID PRIMARY KEY,
    slot_id             UUID        NOT NULL REFERENCES booking_slot (id),
    student_id          UUID        NOT NULL,
    trainer_id          UUID        NOT NULL,
    initiated_by        TEXT        NOT NULL,
    status              TEXT        NOT NULL,
    price_minor         BIGINT      NOT NULL,
    payment_required    BOOLEAN     NOT NULL DEFAULT FALSE,
    payment_id          UUID,
    payment_deadline    TIMESTAMPTZ,
    draft_expires_at    TIMESTAMPTZ,
    comment             TEXT,
    late_cancellation   BOOLEAN     NOT NULL DEFAULT FALSE,
    rescheduled_from_id UUID REFERENCES booking (id),
    reschedule_count    INT         NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    version             INT         NOT NULL DEFAULT 0
);

-- На слот — максимум одно активное бронирование (BR-005.1): последняя линия защиты от двойной записи
CREATE UNIQUE INDEX booking_one_active_per_slot ON booking (slot_id)
    WHERE status IN ('DRAFT', 'AWAITING_COACH_APPROVAL', 'AWAITING_PAYMENT', 'CONFIRMED');

-- Transactional Outbox (раздел 4.3.5) — читается Debezium
CREATE TABLE outbox (
    id             UUID PRIMARY KEY,
    aggregate_type TEXT        NOT NULL,
    aggregate_id   UUID        NOT NULL,
    event_type     TEXT        NOT NULL,
    payload        JSONB       NOT NULL,
    trace_parent   TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Идемпотентные консьюмеры
CREATE TABLE processed_events (
    event_id     UUID NOT NULL,
    consumer     TEXT NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, consumer)
);

CREATE TABLE idempotency_key (
    user_id      UUID        NOT NULL,
    key          UUID        NOT NULL,
    request_hash TEXT        NOT NULL,
    booking_id   UUID        NOT NULL,
    expires_at   TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, key)
);
