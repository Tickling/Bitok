import { randomUUID } from 'node:crypto';

/** Конверт CloudEvents 1.0 (схема: api-contracts/events/cloudevent.envelope.json). */
export interface CloudEvent<T = unknown> {
  specversion: '1.0';
  id: string;
  type: string;
  source: string;
  subject?: string;
  time: string;
  datacontenttype: 'application/json';
  traceparent?: string;
  data: T;
}

export function makeEvent<T>(type: string, source: string, subject: string, data: T, now: Date): CloudEvent<T> {
  return {
    specversion: '1.0',
    id: randomUUID(),
    type,
    source,
    subject,
    time: now.toISOString(),
    datacontenttype: 'application/json',
    data,
  };
}
