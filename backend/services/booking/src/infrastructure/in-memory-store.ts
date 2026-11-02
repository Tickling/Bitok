import type { OutboxRecord } from '@bitok/shared-kernel';
import type { BookingStore, BookingTx, IdempotencyStore } from '../application/ports';
import { Booking, type BookingSnapshot } from '../domain/booking';
import { SLOT_HOLDING } from '../domain/booking-status';
import { BookingSlot, type BookingSlotProps } from '../domain/booking-slot';
import { BookingErrors } from '../domain/errors';
import { DEFAULT_TRAINER_SETTINGS, type TrainerBookingSettings } from '../domain/trainer-settings';

/**
 * In-memory реализация для локального запуска и тестов. Повторяет семантику PostgreSQL-адаптера:
 * чтения возвращают копии, записи буферизуются и применяются атомарно при коммите с проверками:
 *  - CAS по version (оптимистичная блокировка) — аналог UPDATE … WHERE version = $expected;
 *  - уникальность активной брони на слот — аналог частичного индекса booking_one_active_per_slot.
 * Между чтениями и коммитом есть await, поэтому конкурентные транзакции реально чередуются.
 */
export class InMemoryBookingStore implements BookingStore {
  readonly slots = new Map<string, BookingSlotProps>();
  readonly bookings = new Map<string, BookingSnapshot>();
  readonly outbox: OutboxRecord[] = [];
  readonly settings = new Map<string, TrainerBookingSettings>();
  /** Проекция «тренер ↔ ученик» (в проде — по событиям booking.confirmed). */
  readonly coachStudents = new Set<string>();

  addSlot(slot: BookingSlot): void {
    this.slots.set(slot.id, slot.snapshot());
  }

  async transaction<T>(work: (tx: BookingTx) => Promise<T>): Promise<T> {
    const slotWrites: { slot: BookingSlotProps; expected: number }[] = [];
    const bookingInserts: BookingSnapshot[] = [];
    const bookingUpdates: { booking: BookingSnapshot; expected: number }[] = [];
    const outbox: OutboxRecord[] = [];

    const tx: BookingTx = {
      getSlot: async (id) => {
        await Promise.resolve();
        const s = this.slots.get(id);
        return s ? BookingSlot.restore({ ...s }) : null;
      },
      getBooking: async (id) => {
        await Promise.resolve();
        const b = this.bookings.get(id);
        return b ? Booking.restore({ ...b }) : null;
      },
      activeBookingsOfStudent: async (studentId) => {
        await Promise.resolve();
        return [...this.bookings.values()]
          .filter((b) => b.studentId === studentId && SLOT_HOLDING.has(b.status))
          .map((b) => Booking.restore({ ...b }));
      },
      getSettings: async (trainerId) => this.settings.get(trainerId) ?? DEFAULT_TRAINER_SETTINGS,
      isCoachesStudent: async (trainerId, studentId) => this.coachStudents.has(`${trainerId}:${studentId}`),
      saveSlot: (slot, expected) => slotWrites.push({ slot: slot.snapshot(), expected }),
      insertBooking: (b) => bookingInserts.push(b.snapshot()),
      updateBooking: (b, expected) => bookingUpdates.push({ booking: b.snapshot(), expected }),
      appendOutbox: (records) => outbox.push(...records),
    };

    const result = await work(tx);

    // ---- COMMIT: синхронно, без await — атомарно относительно других транзакций ----
    for (const w of slotWrites) {
      const current = this.slots.get(w.slot.id);
      if (!current || current.version !== w.expected) throw BookingErrors.slotAlreadyTaken();
    }
    for (const u of bookingUpdates) {
      const current = this.bookings.get(u.booking.id);
      if (!current || current.version !== u.expected) throw BookingErrors.versionConflict();
    }
    for (const b of bookingInserts) {
      const conflict = [...this.bookings.values()].some((x) => x.slotId === b.slotId && SLOT_HOLDING.has(x.status));
      if (conflict && SLOT_HOLDING.has(b.status)) throw BookingErrors.slotAlreadyTaken();
    }
    for (const w of slotWrites) this.slots.set(w.slot.id, w.slot);
    for (const b of bookingInserts) this.bookings.set(b.id, b);
    for (const u of bookingUpdates) this.bookings.set(u.booking.id, u.booking);
    this.outbox.push(...outbox);
    return result;
  }
}

export class InMemoryIdempotencyStore implements IdempotencyStore {
  private readonly map = new Map<string, { requestHash: string; bookingId: string }>();
  async get(userId: string, key: string) {
    return this.map.get(`${userId}:${key}`) ?? null;
  }
  async put(userId: string, key: string, value: { requestHash: string; bookingId: string }) {
    this.map.set(`${userId}:${key}`, value);
  }
}
