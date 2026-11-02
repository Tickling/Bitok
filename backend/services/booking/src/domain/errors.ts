import { DomainProblem } from '@bitok/shared-kernel';
import type { BookingStatus } from './booking-status';

/** Доменные ошибки → RFC 7807 с машинными кодами из OpenAPI (api-contracts/openapi/booking.yaml). */
export const BookingErrors = {
  notFound: (what: string) => new DomainProblem(404, 'NOT_FOUND', `${what} не найден`),
  slotAlreadyTaken: () => new DomainProblem(409, 'SLOT_ALREADY_TAKEN', 'Слот уже занят'),
  overlappingBooking: () => new DomainProblem(409, 'OVERLAPPING_BOOKING', 'У вас уже есть тренировка в это время'),
  invalidTransition: (from: BookingStatus, to: BookingStatus) =>
    new DomainProblem(409, 'INVALID_STATE_TRANSITION', 'Действие недоступно в текущем статусе', `Переход ${from} → ${to} запрещён`),
  forbidden: () => new DomainProblem(403, 'FORBIDDEN', 'Нет прав на это действие'),
  notCoachesStudent: () => new DomainProblem(403, 'NOT_COACHES_STUDENT', 'Ученик не занимается у этого тренера'),
  reasonRequired: () => new DomainProblem(422, 'REASON_REQUIRED', 'Укажите причину'),
  leadTimeViolation: (minutes: number) =>
    new DomainProblem(422, 'LEAD_TIME_VIOLATION', 'Слишком поздно для записи', `Записаться можно не позднее чем за ${minutes} мин до начала`),
  pendingLimitExceeded: (limit: number) =>
    new DomainProblem(422, 'PENDING_LIMIT_EXCEEDED', 'Слишком много заявок', `Не более ${limit} заявок, ожидающих тренера`),
  rescheduleLimitExceeded: () => new DomainProblem(422, 'RESCHEDULE_LIMIT_EXCEEDED', 'Превышен лимит переносов'),
  paymentMismatch: () => new DomainProblem(409, 'PAYMENT_MISMATCH', 'Платёж не соответствует бронированию'),
  versionConflict: () => new DomainProblem(412, 'PRECONDITION_FAILED', 'Бронирование изменилось, обновите данные'),
  idempotencyKeyReused: () =>
    new DomainProblem(422, 'IDEMPOTENCY_KEY_REUSED', 'Ключ идемпотентности использован с другим запросом'),
};
