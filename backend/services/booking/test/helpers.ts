import { InMemoryProcessedEvents, Money } from '@bitok/shared-kernel';
import { randomUUID } from 'node:crypto';
import {
  ChangeBookingStatusHandler,
  CreateBookingHandler,
  ExpireBookingHandler,
  PaymentSucceededHandler,
} from '../src/application/handlers';
import type { Clock } from '../src/application/ports';
import { BookingSlot } from '../src/domain/booking-slot';
import { FeatureFlagPaymentPolicy, PaymentsDisabledPolicy, type PaymentPolicy } from '../src/domain/payment-policy';
import { DEFAULT_TRAINER_SETTINGS } from '../src/domain/trainer-settings';
import { InMemoryBookingStore, InMemoryIdempotencyStore } from '../src/infrastructure/in-memory-store';

export const COACH = 'coach-1';
export const T0 = new Date('2026-11-02T12:00:00Z');

export class FakeClock implements Clock {
  constructor(public current: Date = T0) {}
  now(): Date {
    return this.current;
  }
  advance(ms: number): void {
    this.current = new Date(this.current.getTime() + ms);
  }
}

export function setup(opts: { paymentsEnabled?: boolean; requiresPrepayment?: boolean } = {}) {
  const store = new InMemoryBookingStore();
  const clock = new FakeClock();
  const policy: PaymentPolicy = opts.paymentsEnabled
    ? new FeatureFlagPaymentPolicy({ isEnabled: async () => true })
    : new PaymentsDisabledPolicy();
  store.settings.set(COACH, { ...DEFAULT_TRAINER_SETTINGS, requiresPrepayment: opts.requiresPrepayment ?? false });
  const slot = BookingSlot.create({
    id: 'slot-1',
    trainerId: COACH,
    clubId: 'club-1',
    startsAt: new Date(T0.getTime() + 48 * 3_600_000),
    durationMinutes: 60,
    price: Money.rubles(2500),
  });
  store.addSlot(slot);
  const ids = { next: () => randomUUID() };
  return {
    store,
    clock,
    slot,
    create: new CreateBookingHandler(store, new InMemoryIdempotencyStore(), policy, clock, ids),
    change: new ChangeBookingStatusHandler(store, policy, clock),
    expire: new ExpireBookingHandler(store, clock),
    paid: new PaymentSucceededHandler(store, new InMemoryProcessedEvents(), clock),
  };
}
