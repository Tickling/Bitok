/** Статусы бронирования и декларативная таблица переходов (ANALYTICS.md, раздел 4.4). */
export const BookingStatus = {
  DRAFT: 'DRAFT',
  AWAITING_COACH_APPROVAL: 'AWAITING_COACH_APPROVAL',
  AWAITING_PAYMENT: 'AWAITING_PAYMENT',
  CONFIRMED: 'CONFIRMED',
  COMPLETED: 'COMPLETED',
  REJECTED_BY_COACH: 'REJECTED_BY_COACH',
  CANCELLED_BY_STUDENT: 'CANCELLED_BY_STUDENT',
  CANCELLED_BY_COACH: 'CANCELLED_BY_COACH',
  EXPIRED: 'EXPIRED',
  RESCHEDULED: 'RESCHEDULED',
  NO_SHOW: 'NO_SHOW',
} as const;
export type BookingStatus = (typeof BookingStatus)[keyof typeof BookingStatus];

const S = BookingStatus;

/** Расширение модели = новая строка таблицы, существующие переходы не меняются. */
export const TRANSITIONS: Readonly<Record<BookingStatus, readonly BookingStatus[]>> = {
  [S.DRAFT]: [S.AWAITING_COACH_APPROVAL, S.EXPIRED, S.CANCELLED_BY_STUDENT],
  [S.AWAITING_COACH_APPROVAL]: [S.CONFIRMED, S.AWAITING_PAYMENT, S.REJECTED_BY_COACH, S.CANCELLED_BY_STUDENT, S.EXPIRED],
  [S.AWAITING_PAYMENT]: [S.CONFIRMED, S.EXPIRED, S.CANCELLED_BY_STUDENT, S.CANCELLED_BY_COACH],
  [S.CONFIRMED]: [S.COMPLETED, S.CANCELLED_BY_STUDENT, S.CANCELLED_BY_COACH, S.RESCHEDULED, S.NO_SHOW],
  [S.COMPLETED]: [],
  [S.REJECTED_BY_COACH]: [],
  [S.CANCELLED_BY_STUDENT]: [],
  [S.CANCELLED_BY_COACH]: [],
  [S.EXPIRED]: [],
  [S.RESCHEDULED]: [],
  [S.NO_SHOW]: [],
};

/** Статусы, удерживающие слот (уникальный частичный индекс booking_one_active_per_slot). */
export const SLOT_HOLDING: ReadonlySet<BookingStatus> = new Set([
  S.DRAFT,
  S.AWAITING_COACH_APPROVAL,
  S.AWAITING_PAYMENT,
  S.CONFIRMED,
]);

export function canTransition(from: BookingStatus, to: BookingStatus): boolean {
  return TRANSITIONS[from].includes(to);
}
