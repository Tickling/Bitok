import { createHash } from 'node:crypto';
import { makeEvent, type ProcessedEvents } from '@bitok/shared-kernel';
import { Booking, type BookingActor, type CancellationReason } from '../domain/booking';
import { BookingStatus } from '../domain/booking-status';
import { BookingErrors } from '../domain/errors';
import type { PaymentPolicy } from '../domain/payment-policy';
import { toOutbox } from './outbox-mapper';
import type { BookingStore, Clock, IdempotencyStore, IdGenerator } from './ports';

export const MAX_AWAITING_APPROVAL = 3;

export interface CreateBookingCommand {
  studentId: string;
  slotId: string;
  comment: string | null;
  idempotencyKey: string;
  /** DRAFT — двухшаговый UX: слот удерживается 5 минут, затем действие SUBMIT. */
  mode?: 'REQUEST' | 'DRAFT';
}

/** FR-005: бронирование слота учеником. Идемпотентно по Idempotency-Key. */
export class CreateBookingHandler {
  constructor(
    private readonly store: BookingStore,
    private readonly idempotency: IdempotencyStore,
    private readonly policy: PaymentPolicy,
    private readonly clock: Clock,
    private readonly ids: IdGenerator,
  ) {}

  async execute(cmd: CreateBookingCommand): Promise<{ booking: Booking; replayed: boolean }> {
    const requestHash = createHash('sha256').update(JSON.stringify([cmd.slotId, cmd.comment, cmd.mode ?? 'REQUEST'])).digest('hex');
    const previous = await this.idempotency.get(cmd.studentId, cmd.idempotencyKey);
    if (previous) {
      if (previous.requestHash !== requestHash) throw BookingErrors.idempotencyKeyReused();
      const booking = await this.store.transaction((tx) => tx.getBooking(previous.bookingId));
      if (!booking) throw BookingErrors.notFound('Бронирование');
      return { booking, replayed: true };
    }

    const now = this.clock.now();
    const booking = await this.store.transaction(async (tx) => {
      const slot = await tx.getSlot(cmd.slotId);
      if (!slot) throw BookingErrors.notFound('Слот');
      const settings = await tx.getSettings(slot.trainerId);

      if (slot.startsAt.getTime() - now.getTime() < settings.minLeadTimeMinutes * 60_000) {
        throw BookingErrors.leadTimeViolation(settings.minLeadTimeMinutes);
      }
      const active = await tx.activeBookingsOfStudent(cmd.studentId);
      if (active.filter((b) => b.status === BookingStatus.AWAITING_COACH_APPROVAL).length >= MAX_AWAITING_APPROVAL) {
        throw BookingErrors.pendingLimitExceeded(MAX_AWAITING_APPROVAL);
      }
      const end = slot.endsAt.getTime();
      const overlaps = active.some((b) => {
        const s = b.startsAt.getTime();
        return s < end && slot.startsAt.getTime() < s + b.snapshot().durationMinutes * 60_000;
      });
      if (overlaps) throw BookingErrors.overlappingBooking();

      const expectedSlotVersion = slot.version;
      const created =
        cmd.mode === 'DRAFT'
          ? Booking.reserveDraft(this.ids.next(), slot, cmd.studentId, now)
          : Booking.request(this.ids.next(), slot, cmd.studentId, cmd.comment, now);
      if (settings.autoConfirm && created.status === BookingStatus.AWAITING_COACH_APPROVAL) {
        created.approve({ kind: 'coach', id: slot.trainerId }, await this.policy.decide(created, settings), now);
      }
      if (created.status === BookingStatus.CONFIRMED) {
        slot.hold(now, now);
        slot.markBooked();
      } else {
        slot.hold(created.slotHoldDeadline ?? created.approvalExpiresAt, now);
      }
      tx.saveSlot(slot, expectedSlotVersion);
      tx.insertBooking(created);
      tx.appendOutbox(toOutbox(created.pullEvents(), now));
      return created;
    });

    await this.idempotency.put(cmd.studentId, cmd.idempotencyKey, { requestHash, bookingId: booking.id });
    return { booking, replayed: false };
  }
}

export type StatusAction =
  | { action: 'SUBMIT'; comment: string | null }
  | { action: 'APPROVE' }
  | { action: 'REJECT'; reason: CancellationReason | null }
  | { action: 'CANCEL'; reason: CancellationReason | null }
  | { action: 'COMPLETE' }
  | { action: 'NO_SHOW' };

/** FR-006/007: команды перехода state machine с If-Match (expectedVersion). */
export class ChangeBookingStatusHandler {
  constructor(
    private readonly store: BookingStore,
    private readonly policy: PaymentPolicy,
    private readonly clock: Clock,
  ) {}

  async execute(bookingId: string, actor: BookingActor, cmd: StatusAction, expectedVersion: number): Promise<Booking> {
    const now = this.clock.now();
    return this.store.transaction(async (tx) => {
      const booking = await tx.getBooking(bookingId);
      if (!booking) throw BookingErrors.notFound('Бронирование');
      if (booking.version !== expectedVersion) throw BookingErrors.versionConflict();
      const slot = await tx.getSlot(booking.slotId);
      if (!slot) throw BookingErrors.notFound('Слот');
      const slotVersion = slot.version;
      const settings = await tx.getSettings(booking.trainerId);

      switch (cmd.action) {
        case 'SUBMIT':
          booking.submit(actor, cmd.comment, now);
          if (booking.slotHoldDeadline) slot.resetHold(booking.slotHoldDeadline);
          break;
        case 'APPROVE': {
          booking.approve(actor, await this.policy.decide(booking, settings), now);
          if (booking.status === BookingStatus.CONFIRMED) slot.markBooked();
          else if (booking.slotHoldDeadline) slot.resetHold(booking.slotHoldDeadline);
          break;
        }
        case 'REJECT':
          booking.reject(actor, cmd.reason, now);
          slot.release();
          break;
        case 'CANCEL':
          booking.cancel(actor, cmd.reason, settings.freeCancellationHours, now);
          slot.release();
          break;
        case 'COMPLETE':
          booking.complete(now);
          break;
        case 'NO_SHOW':
          booking.markNoShow(actor, now);
          break;
      }
      if (slot.version !== slotVersion) tx.saveSlot(slot, slotVersion);
      tx.updateBooking(booking, expectedVersion);
      tx.appendOutbox(toOutbox(booking.pullEvents(), now));
      return booking;
    });
  }
}

/** Планировщик: истечение заявок и неоплаченных броней (таймеры в БД, FOR UPDATE SKIP LOCKED). */
export class ExpireBookingHandler {
  constructor(
    private readonly store: BookingStore,
    private readonly clock: Clock,
  ) {}

  async execute(bookingId: string): Promise<boolean> {
    const now = this.clock.now();
    return this.store.transaction(async (tx) => {
      const booking = await tx.getBooking(bookingId);
      const deadline = booking?.expiresAt();
      if (!booking || !deadline || deadline.getTime() > now.getTime()) return false;
      const slot = await tx.getSlot(booking.slotId);
      const version = booking.version;
      booking.expire(now);
      if (slot) {
        const slotVersion = slot.version;
        slot.release();
        tx.saveSlot(slot, slotVersion);
      }
      tx.updateBooking(booking, version);
      tx.appendOutbox(toOutbox(booking.pullEvents(), now));
      return true;
    });
  }
}

export interface PaymentSucceededEvent {
  eventId: string;
  paymentId: string;
  bookingId: string;
  amountMinor: number;
}

/**
 * Консьюмер PaymentSucceeded (шаг T4→T5 саги). Идемпотентен (processed_events).
 * Если бронь уже потеряна — публикует BookingPaymentRejected → Payment делает возврат (C4).
 */
export class PaymentSucceededHandler {
  constructor(
    private readonly store: BookingStore,
    private readonly processed: ProcessedEvents,
    private readonly clock: Clock,
  ) {}

  async execute(e: PaymentSucceededEvent): Promise<'confirmed' | 'refund_requested' | 'duplicate'> {
    if (!(await this.processed.markProcessed(e.eventId, 'booking.payment-succeeded'))) return 'duplicate';
    const now = this.clock.now();
    return this.store.transaction(async (tx) => {
      const booking = await tx.getBooking(e.bookingId);
      if (!booking) throw BookingErrors.notFound('Бронирование');
      if (booking.status === BookingStatus.AWAITING_PAYMENT || booking.status === BookingStatus.CONFIRMED) {
        const version = booking.version;
        booking.markPaid(e.paymentId, { amountMinor: e.amountMinor, currency: 'RUB' }, now);
        const slot = await tx.getSlot(booking.slotId);
        if (slot && slot.status !== 'BOOKED') {
          const slotVersion = slot.version;
          slot.markBooked();
          tx.saveSlot(slot, slotVersion);
        }
        if (booking.version !== version) tx.updateBooking(booking, version);
        tx.appendOutbox(toOutbox(booking.pullEvents(), now));
        return 'confirmed';
      }
      // Оплата пришла, но бронь уже EXPIRED / отменена → компенсация: возврат.
      tx.appendOutbox([
        {
          aggregateType: 'booking',
          aggregateId: booking.id,
          event: makeEvent(
            'booking.payment_rejected',
            'booking-service',
            `booking/${booking.id}`,
            { bookingId: booking.id, paymentId: e.paymentId, reason: booking.status === BookingStatus.EXPIRED ? 'SLOT_LOST' : 'CANCELLED' },
            now,
          ),
        },
      ]);
      return 'refund_requested';
    });
  }
}
