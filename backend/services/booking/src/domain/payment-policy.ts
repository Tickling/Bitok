import type { Money } from '@bitok/shared-kernel';
import type { Booking } from './booking';
import type { TrainerBookingSettings } from './trainer-settings';

/** ЕДИНСТВЕННОЕ место ветвления «нужна ли оплата» (ADR-008). Домен не знает о флагах. */
export type PaymentDecision =
  | { kind: 'notRequired' }
  | { kind: 'required'; amount: Money; ttlSeconds: number };

export interface PaymentPolicy {
  decide(booking: Booking, settings: TrainerBookingSettings): Promise<PaymentDecision>;
}

export interface FeatureFlags {
  isEnabled(flag: 'paymentsEnabled' | 'refundsEnabled' | 'shopEnabled', ctx: { trainerId?: string }): Promise<boolean>;
}

/** MVP: оплата выключена — маршрут AWAITING_COACH_APPROVAL → CONFIRMED. */
export class PaymentsDisabledPolicy implements PaymentPolicy {
  async decide(): Promise<PaymentDecision> {
    return { kind: 'notRequired' };
  }
}

/** v1.0: флаг `paymentsEnabled` + требование предоплаты тренером. */
export class FeatureFlagPaymentPolicy implements PaymentPolicy {
  static readonly PAYMENT_TTL_SECONDS = 15 * 60;

  constructor(private readonly flags: FeatureFlags) {}

  async decide(booking: Booking, settings: TrainerBookingSettings): Promise<PaymentDecision> {
    const enabled = await this.flags.isEnabled('paymentsEnabled', { trainerId: booking.trainerId });
    return enabled && settings.requiresPrepayment && booking.price.amountMinor > 0
      ? { kind: 'required', amount: booking.price, ttlSeconds: FeatureFlagPaymentPolicy.PAYMENT_TTL_SECONDS }
      : { kind: 'notRequired' };
  }
}
