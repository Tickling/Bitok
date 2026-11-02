import { Controller, Get, Module } from '@nestjs/common';
import { Money } from '@bitok/shared-kernel';
import { BookingsController } from './api/bookings.controller';
import { CLOCK, PAYMENT_GATEWAY, POLICY, STORE } from './api/tokens';
import { ChangeBookingStatusHandler, CreateBookingHandler } from './application/handlers';
import type { BookingStore, Clock } from './application/ports';
import { BookingSlot } from './domain/booking-slot';
import { FeatureFlagPaymentPolicy, PaymentsDisabledPolicy, type PaymentPolicy } from './domain/payment-policy';
import { InMemoryBookingStore, InMemoryIdempotencyStore } from './infrastructure/in-memory-store';
import { NoopPaymentGateway } from './infrastructure/noop-payment-gateway';
import { systemClock, uuidGenerator } from './infrastructure/system';

@Controller('health')
class HealthController {
  @Get('live') live() { return { status: 'UP' }; }
  @Get('ready') ready() { return { status: 'UP' }; }
}

/** Демо-данные для локального запуска (STORE_ADAPTER=memory). В проде — PostgreSQL-адаптер. */
function seedDemo(store: InMemoryBookingStore): void {
  const base = new Date();
  base.setUTCHours(15, 0, 0, 0);
  for (let day = 2; day <= 4; day++) {
    for (let hour = 0; hour < 3; hour++) {
      store.addSlot(BookingSlot.create({
        id: `demo-slot-${day}-${hour}`,
        trainerId: 'demo-coach',
        clubId: 'demo-club',
        startsAt: new Date(base.getTime() + day * 86_400_000 + hour * 3_600_000),
        durationMinutes: 60,
        price: Money.rubles(2500),
      }));
    }
  }
}

/**
 * Composition root: выбор адаптеров по окружению — ядро бронирования не меняется (Ports & Adapters).
 *  PAYMENTS_ENABLED=true → FeatureFlagPaymentPolicy (в проде флаг читается из Unleash).
 */
@Module({
  controllers: [BookingsController, HealthController],
  providers: [
    { provide: CLOCK, useValue: systemClock },
    {
      provide: STORE,
      useFactory: () => {
        const store = new InMemoryBookingStore();
        if (process.env.SEED_DEMO !== 'false') seedDemo(store);
        return store;
      },
    },
    {
      provide: POLICY,
      useFactory: (): PaymentPolicy =>
        process.env.PAYMENTS_ENABLED === 'true'
          ? new FeatureFlagPaymentPolicy({ isEnabled: async () => true })
          : new PaymentsDisabledPolicy(),
    },
    { provide: PAYMENT_GATEWAY, useValue: new NoopPaymentGateway() },
    {
      provide: CreateBookingHandler,
      inject: [STORE, POLICY, CLOCK],
      useFactory: (store: BookingStore, policy: PaymentPolicy, clock: Clock) =>
        new CreateBookingHandler(store, new InMemoryIdempotencyStore(), policy, clock, uuidGenerator),
    },
    {
      provide: ChangeBookingStatusHandler,
      inject: [STORE, POLICY, CLOCK],
      useFactory: (store: BookingStore, policy: PaymentPolicy, clock: Clock) => new ChangeBookingStatusHandler(store, policy, clock),
    },
  ],
})
export class AppModule {}
