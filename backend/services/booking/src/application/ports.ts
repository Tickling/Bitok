import type { OutboxRecord } from '@bitok/shared-kernel';
import type { Booking } from '../domain/booking';
import type { BookingSlot } from '../domain/booking-slot';
import type { TrainerBookingSettings } from '../domain/trainer-settings';

export interface Clock {
  now(): Date;
}

export interface IdGenerator {
  next(): string;
}

/**
 * Единица работы: все изменения внутри `work` фиксируются атомарно (одна транзакция PostgreSQL):
 * CAS слота по version, уникальность активной брони на слот, вставка брони и записей Outbox.
 * При конфликте коммит падает с BookingErrors.slotAlreadyTaken / versionConflict.
 */
export interface BookingStore {
  transaction<T>(work: (tx: BookingTx) => Promise<T>): Promise<T>;
}

export interface BookingTx {
  getSlot(id: string): Promise<BookingSlot | null>;
  getBooking(id: string): Promise<Booking | null>;
  activeBookingsOfStudent(studentId: string): Promise<Booking[]>;
  getSettings(trainerId: string): Promise<TrainerBookingSettings>;
  isCoachesStudent(trainerId: string, studentId: string): Promise<boolean>;
  /** Оптимистичная блокировка: применится, только если версия в хранилище = expectedVersion. */
  saveSlot(slot: BookingSlot, expectedVersion: number): void;
  insertBooking(booking: Booking): void;
  updateBooking(booking: Booking, expectedVersion: number): void;
  appendOutbox(records: OutboxRecord[]): void;
}

/** Порт к платёжному контуру (ADR-008). MVP: NoopPaymentGateway. */
export interface PaymentGateway {
  createSession(cmd: { bookingId: string; payerId: string; amountMinor: number; expiresAt: Date }): Promise<{
    paymentId: string;
    paymentUrl: string;
    expiresAt: Date;
  }>;
  cancelSession(paymentId: string): Promise<void>;
  requestRefund(cmd: { paymentId: string; amountMinor: number; reason: string }): Promise<void>;
}

export interface IdempotencyStore {
  get(userId: string, key: string): Promise<{ requestHash: string; bookingId: string } | null>;
  put(userId: string, key: string, value: { requestHash: string; bookingId: string }): Promise<void>;
}
