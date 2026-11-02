import { makeEvent, type OutboxRecord } from '@bitok/shared-kernel';
import type { BookingDomainEvent } from '../domain/booking';

const SOURCE = 'booking-service';

/** Доменное событие → CloudEvent для Outbox. Телефонов и прочих ПДн в событиях нет (9.2.9). */
export function toOutbox(events: BookingDomainEvent[], now: Date): OutboxRecord[] {
  return events.map((e) => {
    const b = e.booking;
    const base = {
      bookingId: b.id,
      slotId: b.slotId,
      studentId: b.studentId,
      trainerId: b.trainerId,
      startsAt: b.startsAt.toISOString(),
      durationMinutes: b.durationMinutes,
      status: b.status,
      version: b.version,
    };
    const data =
      e.type === 'booking.confirmed_by_coach'
        ? {
            ...base,
            paymentRequired: e.paymentRequired,
            ...(e.paymentRequired ? { amount: b.price, paymentDeadline: b.paymentDeadline?.toISOString() } : {}),
          }
        : e.type === 'booking.cancelled'
          ? { ...base, cancelledBy: e.cancelledBy, lateCancellation: b.lateCancellation, paymentId: b.paymentId }
          : e.type === 'booking.expired'
            ? { ...base, previousStatus: e.previousStatus }
            : base;
    return { aggregateType: 'booking', aggregateId: b.id, event: makeEvent(e.type, SOURCE, `booking/${b.id}`, data, now) };
  });
}
