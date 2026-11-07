import type { CloudEvent } from './events';

/**
 * Transactional Outbox (раздел 4.3.5). События пишутся В ТОЙ ЖЕ транзакции, что и агрегат;
 * публикацию в Kafka выполняет Debezium (CDC). Бизнес-код никогда не вызывает Kafka напрямую.
 */
export interface OutboxRecord {
  aggregateType: string;
  aggregateId: string; // ключ партиции Kafka — порядок событий агрегата
  event: CloudEvent;
}

/** Идемпотентный консьюмер: эффект и отметка «обработано» — в одной транзакции. */
export interface ProcessedEvents {
  /** true — событие новое и помечено; false — дубликат (at-least-once доставка). */
  markProcessed(eventId: string, consumer: string): Promise<boolean>;
}

export class InMemoryProcessedEvents implements ProcessedEvents {
  private readonly seen = new Set<string>();
  async markProcessed(eventId: string, consumer: string): Promise<boolean> {
    const key = `${consumer}:${eventId}`;
    if (this.seen.has(key)) return false;
    this.seen.add(key);
    return true;
  }
}
