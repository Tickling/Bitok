import { DomainProblem } from '@bitok/shared-kernel';
import { describe, expect, it } from 'vitest';
import { Booking } from '../src/domain/booking';
import { canTransition, TRANSITIONS } from '../src/domain/booking-status';
import { COACH, setup } from './helpers';

const student = (n = 1) => `student-${n}`;
const code = (e: unknown) => (e instanceof DomainProblem ? e.code : String(e));

describe('State machine', () => {
  it('терминальные статусы не имеют переходов', () => {
    for (const s of ['COMPLETED', 'REJECTED_BY_COACH', 'EXPIRED', 'CANCELLED_BY_STUDENT', 'CANCELLED_BY_COACH', 'NO_SHOW'] as const) {
      expect(TRANSITIONS[s]).toHaveLength(0);
    }
    expect(canTransition('EXPIRED', 'CONFIRMED')).toBe(false);
  });

  it('paymentsEnabled = false: AWAITING_COACH_APPROVAL → CONFIRMED, слот BOOKED', async () => {
    const t = setup();
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    expect(booking.status).toBe('AWAITING_COACH_APPROVAL');
    expect(t.store.slots.get('slot-1')?.status).toBe('HELD');

    const approved = await t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'APPROVE' }, booking.version);
    expect(approved.status).toBe('CONFIRMED');
    expect(t.store.slots.get('slot-1')?.status).toBe('BOOKED');
    expect(t.store.outbox.map((r) => r.event.type)).toEqual([
      'booking.requested',
      'booking.confirmed_by_coach',
      'booking.confirmed',
    ]);
  });

  it('paymentsEnabled = true: → AWAITING_PAYMENT, холд слота = дедлайн оплаты + grace', async () => {
    const t = setup({ paymentsEnabled: true, requiresPrepayment: true });
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    const approved = await t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'APPROVE' }, booking.version);
    expect(approved.status).toBe('AWAITING_PAYMENT');
    const deadline = approved.paymentDeadline!.getTime();
    expect(deadline).toBe(t.clock.now().getTime() + 15 * 60_000);
    expect(t.store.slots.get('slot-1')?.heldUntil?.getTime()).toBe(deadline + Booking.PAYMENT_GRACE_MS);
    const event = t.store.outbox.find((r) => r.event.type === 'booking.confirmed_by_coach')!;
    expect((event.event.data as { paymentRequired: boolean }).paymentRequired).toBe(true);
  });

  it('флаг включён, но тренер не требует предоплату → оплата пропускается', async () => {
    const t = setup({ paymentsEnabled: true, requiresPrepayment: false });
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    const approved = await t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'APPROVE' }, booking.version);
    expect(approved.status).toBe('CONFIRMED');
  });

  it('ученик не может подтвердить свою заявку', async () => {
    const t = setup();
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    await expect(
      t.change.execute(booking.id, { kind: 'student', id: student() }, { action: 'APPROVE' }, booking.version),
    ).rejects.toMatchObject({ code: 'FORBIDDEN' });
  });

  it('устаревший ETag → 412', async () => {
    const t = setup();
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    await t.change.execute(booking.id, { kind: 'student', id: student() }, { action: 'CANCEL', reason: null }, booking.version);
    await expect(
      t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'APPROVE' }, booking.version),
    ).rejects.toMatchObject({ status: 412 });
  });

  it('отклонение требует причину и освобождает слот', async () => {
    const t = setup();
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    await expect(
      t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'REJECT', reason: null }, booking.version),
    ).rejects.toMatchObject({ code: 'REASON_REQUIRED' });
    await t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'REJECT', reason: { code: 'SCHEDULE_CONFLICT' } }, booking.version);
    expect(t.store.slots.get('slot-1')?.status).toBe('AVAILABLE');
  });
});

describe('Конкурентность и идемпотентность', () => {
  it('100 параллельных броней одного слота → ровно одна успешна (AC-005.2)', async () => {
    const t = setup();
    const results = await Promise.allSettled(
      Array.from({ length: 100 }, (_, i) =>
        t.create.execute({ studentId: student(i), slotId: 'slot-1', comment: null, idempotencyKey: `k-${i}` }),
      ),
    );
    const ok = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
    expect(ok).toHaveLength(1);
    expect(rejected.every((r) => code(r.reason) === 'SLOT_ALREADY_TAKEN')).toBe(true);
    const active = [...t.store.bookings.values()].filter((b) => b.slotId === 'slot-1');
    expect(active).toHaveLength(1);
  });

  it('повтор с тем же Idempotency-Key возвращает ту же бронь (AC-005.3)', async () => {
    const t = setup();
    const first = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: 'выход', idempotencyKey: 'same' });
    const second = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: 'выход', idempotencyKey: 'same' });
    expect(second.replayed).toBe(true);
    expect(second.booking.id).toBe(first.booking.id);
    expect(t.store.bookings.size).toBe(1);
  });

  it('тот же ключ с другим телом → 422 IDEMPOTENCY_KEY_REUSED', async () => {
    const t = setup();
    await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: 'a', idempotencyKey: 'same' });
    await expect(
      t.create.execute({ studentId: student(), slotId: 'slot-1', comment: 'b', idempotencyKey: 'same' }),
    ).rejects.toMatchObject({ code: 'IDEMPOTENCY_KEY_REUSED' });
  });

  it('запись позже чем за 2 часа → LEAD_TIME_VIOLATION', async () => {
    const t = setup();
    t.clock.advance(47 * 3_600_000);
    await expect(
      t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k' }),
    ).rejects.toMatchObject({ code: 'LEAD_TIME_VIOLATION' });
  });
});

describe('Saga оплаты: TTL холда vs оплата', () => {
  async function awaitingPayment() {
    const t = setup({ paymentsEnabled: true, requiresPrepayment: true });
    const { booking } = await t.create.execute({ studentId: student(), slotId: 'slot-1', comment: null, idempotencyKey: 'k1' });
    const approved = await t.change.execute(booking.id, { kind: 'coach', id: COACH }, { action: 'APPROVE' }, booking.version);
    return { t, booking: approved };
  }

  it('оплата в срок → CONFIRMED; повторный webhook обрабатывается один раз', async () => {
    const { t, booking } = await awaitingPayment();
    const event = { eventId: 'evt-1', paymentId: 'pay-1', bookingId: booking.id, amountMinor: 250_000 };
    expect(await t.paid.execute(event)).toBe('confirmed');
    expect(await t.paid.execute(event)).toBe('duplicate');
    expect(t.store.bookings.get(booking.id)?.status).toBe('CONFIRMED');
    expect(t.store.slots.get('slot-1')?.status).toBe('BOOKED');
    expect(t.store.outbox.filter((r) => r.event.type === 'booking.confirmed')).toHaveLength(1);
  });

  it('в grace-период (после дедлайна оплаты) слот ещё не отдан — поздний webhook успевает', async () => {
    const { t, booking } = await awaitingPayment();
    t.clock.advance(17 * 60_000); // дедлайн 15 мин прошёл, grace 5 мин ещё нет
    expect(await t.expire.execute(booking.id)).toBe(false);
    expect(await t.paid.execute({ eventId: 'e', paymentId: 'pay-1', bookingId: booking.id, amountMinor: 250_000 })).toBe('confirmed');
  });

  it('оплата после истечения и потери слота → BookingPaymentRejected (компенсация: возврат)', async () => {
    const { t, booking } = await awaitingPayment();
    t.clock.advance(21 * 60_000);
    expect(await t.expire.execute(booking.id)).toBe(true);
    expect(t.store.slots.get('slot-1')?.status).toBe('AVAILABLE');
    await t.create.execute({ studentId: student(2), slotId: 'slot-1', comment: null, idempotencyKey: 'k2' });

    const outcome = await t.paid.execute({ eventId: 'late', paymentId: 'pay-1', bookingId: booking.id, amountMinor: 250_000 });
    expect(outcome).toBe('refund_requested');
    expect(t.store.outbox.at(-1)?.event.type).toBe('booking.payment_rejected');
  });

  it('гонка «истечь» и «оплачено» одновременно → ровно один победитель', async () => {
    const { t, booking } = await awaitingPayment();
    t.clock.advance(21 * 60_000);
    const [expired, paid] = await Promise.allSettled([
      t.expire.execute(booking.id),
      t.paid.execute({ eventId: 'race', paymentId: 'pay-1', bookingId: booking.id, amountMinor: 250_000 }),
    ]);
    const status = t.store.bookings.get(booking.id)?.status;
    const winners = [expired.status === 'fulfilled' && expired.value === true, paid.status === 'fulfilled' && paid.value === 'confirmed'];
    expect(winners.filter(Boolean)).toHaveLength(1);
    expect(['EXPIRED', 'CONFIRMED']).toContain(status);
  });
});
