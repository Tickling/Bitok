import { Money } from '@bitok/shared-kernel';
import { BookingStatus, SLOT_HOLDING, canTransition } from './booking-status';
import type { BookingSlot } from './booking-slot';
import { BookingErrors } from './errors';
import type { PaymentDecision } from './payment-policy';

export type BookingActor =
  | { kind: 'student'; id: string }
  | { kind: 'coach'; id: string }
  | { kind: 'system' };

export type BookingAction = 'SUBMIT' | 'APPROVE' | 'REJECT' | 'CANCEL' | 'PAY' | 'COMPLETE' | 'NO_SHOW' | 'RESCHEDULE';

export interface CancellationReason {
  code: 'ILLNESS' | 'SCHEDULE_CONFLICT' | 'COACH_UNAVAILABLE' | 'CLUB_CLOSED' | 'OTHER';
  text?: string;
}

/** Доменные события агрегата; application-слой кладёт их в Outbox в той же транзакции. */
export type BookingDomainEvent =
  | { type: 'booking.requested'; booking: BookingSnapshot }
  | { type: 'booking.confirmed_by_coach'; booking: BookingSnapshot; paymentRequired: boolean }
  | { type: 'booking.confirmed'; booking: BookingSnapshot }
  | { type: 'booking.rejected_by_coach'; booking: BookingSnapshot }
  | { type: 'booking.cancelled'; booking: BookingSnapshot; cancelledBy: 'STUDENT' | 'COACH' }
  | { type: 'booking.expired'; booking: BookingSnapshot; previousStatus: BookingStatus }
  | { type: 'booking.completed'; booking: BookingSnapshot }
  | { type: 'booking.no_show'; booking: BookingSnapshot };

export interface BookingSnapshot {
  id: string;
  slotId: string;
  studentId: string;
  trainerId: string;
  initiatedBy: 'STUDENT' | 'COACH';
  startsAt: Date;
  durationMinutes: number;
  price: Money;
  status: BookingStatus;
  paymentRequired: boolean;
  paymentId: string | null;
  paymentDeadline: Date | null;
  draftExpiresAt: Date | null;
  comment: string | null;
  cancellationReason: CancellationReason | null;
  lateCancellation: boolean;
  rescheduleCount: number;
  createdAt: Date;
  updatedAt: Date;
  version: number;
}

export class Booking {
  static readonly DRAFT_TTL_MS = 5 * 60_000;
  static readonly APPROVAL_TTL_MS = 24 * 3_600_000;
  static readonly PAYMENT_GRACE_MS = 5 * 60_000;
  static readonly MAX_RESCHEDULES = 2;

  private events: BookingDomainEvent[] = [];

  private constructor(private s: BookingSnapshot) {}

  // ---------- Factories ----------

  /** Основной сценарий: заявка сразу уходит тренеру. */
  static request(id: string, slot: BookingSlot, studentId: string, comment: string | null, now: Date): Booking {
    const booking = Booking.make(id, slot, studentId, 'STUDENT', BookingStatus.AWAITING_COACH_APPROVAL, comment, now);
    booking.record({ type: 'booking.requested', booking: booking.snapshot() });
    return booking;
  }

  /** Двухшаговый UX: слот удерживается 5 минут, пока ученик заполняет детали. */
  static reserveDraft(id: string, slot: BookingSlot, studentId: string, now: Date): Booking {
    const booking = Booking.make(id, slot, studentId, 'STUDENT', BookingStatus.DRAFT, null, now);
    booking.s.draftExpiresAt = new Date(now.getTime() + Booking.DRAFT_TTL_MS);
    return booking;
  }

  /** FR-028: тренер назначает время своему ученику; оплата — по той же PaymentPolicy. */
  static assignByCoach(
    id: string,
    slot: BookingSlot,
    studentId: string,
    coachId: string,
    isCoachesStudent: boolean,
    decision: PaymentDecision,
    now: Date,
  ): Booking {
    if (coachId !== slot.trainerId) throw BookingErrors.forbidden();
    if (!isCoachesStudent) throw BookingErrors.notCoachesStudent();
    const booking = Booking.make(id, slot, studentId, 'COACH', BookingStatus.AWAITING_COACH_APPROVAL, null, now);
    booking.apply(decision, now);
    return booking;
  }

  static restore(s: BookingSnapshot): Booking {
    return new Booking({ ...s });
  }

  private static make(
    id: string,
    slot: BookingSlot,
    studentId: string,
    initiatedBy: 'STUDENT' | 'COACH',
    status: BookingStatus,
    comment: string | null,
    now: Date,
  ): Booking {
    if (!slot.isBookable(now)) throw BookingErrors.slotAlreadyTaken();
    return new Booking({
      id,
      slotId: slot.id,
      studentId,
      trainerId: slot.trainerId,
      initiatedBy,
      startsAt: slot.startsAt,
      durationMinutes: slot.durationMinutes,
      price: slot.price,
      status,
      paymentRequired: false,
      paymentId: null,
      paymentDeadline: null,
      draftExpiresAt: null,
      comment,
      cancellationReason: null,
      lateCancellation: false,
      rescheduleCount: 0,
      createdAt: now,
      updatedAt: now,
      version: 0,
    });
  }

  // ---------- Getters ----------

  get id() { return this.s.id; }
  get slotId() { return this.s.slotId; }
  get studentId() { return this.s.studentId; }
  get trainerId() { return this.s.trainerId; }
  get status() { return this.s.status; }
  get price() { return this.s.price; }
  get startsAt() { return this.s.startsAt; }
  get paymentId() { return this.s.paymentId; }
  get paymentDeadline() { return this.s.paymentDeadline; }
  get version() { return this.s.version; }
  get holdsSlot(): boolean { return SLOT_HOLDING.has(this.s.status); }

  /** Момент автоматического истечения заявки (BR-005.5). */
  get approvalExpiresAt(): Date {
    return new Date(Math.min(this.s.createdAt.getTime() + Booking.APPROVAL_TTL_MS, this.s.startsAt.getTime() - 2 * 3_600_000));
  }

  /** До какого момента держать слот. При оплате — дедлайн + grace: защита от race «TTL vs оплата». */
  get slotHoldDeadline(): Date | null {
    switch (this.s.status) {
      case BookingStatus.DRAFT:
        return this.s.draftExpiresAt;
      case BookingStatus.AWAITING_COACH_APPROVAL:
        return this.approvalExpiresAt;
      case BookingStatus.AWAITING_PAYMENT:
        return this.s.paymentDeadline ? new Date(this.s.paymentDeadline.getTime() + Booking.PAYMENT_GRACE_MS) : null;
      default:
        return null;
    }
  }

  /** Срок, после которого планировщик истекает бронь (null — не истекает). */
  expiresAt(): Date | null {
    return this.slotHoldDeadline;
  }

  /** Действия, доступные актору. Возвращаются клиенту в `allowedActions` (сервер — источник правды для UI). */
  allowedActions(actor: BookingActor, now: Date): BookingAction[] {
    const isStudent = actor.kind === 'student' && actor.id === this.s.studentId;
    const isCoach = actor.kind === 'coach' && actor.id === this.s.trainerId;
    const before = now.getTime() < this.s.startsAt.getTime();
    let actions: BookingAction[] = [];
    switch (this.s.status) {
      case BookingStatus.DRAFT:
        actions = isStudent ? ['SUBMIT', 'CANCEL'] : [];
        break;
      case BookingStatus.AWAITING_COACH_APPROVAL:
        actions = isCoach ? ['APPROVE', 'REJECT'] : isStudent ? ['CANCEL'] : [];
        break;
      case BookingStatus.AWAITING_PAYMENT:
        actions = isStudent ? ['PAY', 'CANCEL'] : isCoach ? ['CANCEL'] : [];
        break;
      case BookingStatus.CONFIRMED:
        if (isCoach) actions = before ? ['CANCEL', 'RESCHEDULE'] : ['COMPLETE', 'NO_SHOW'];
        else if (isStudent) actions = before ? ['CANCEL', 'RESCHEDULE'] : [];
        break;
      default:
        actions = [];
    }
    return this.s.rescheduleCount >= Booking.MAX_RESCHEDULES ? actions.filter((a) => a !== 'RESCHEDULE') : actions;
  }

  // ---------- Transitions ----------

  submit(actor: BookingActor, comment: string | null, now: Date): void {
    if (!(actor.kind === 'student' && actor.id === this.s.studentId)) throw BookingErrors.forbidden();
    this.transition(BookingStatus.AWAITING_COACH_APPROVAL, now);
    this.s.comment = comment;
    this.s.draftExpiresAt = null;
    this.record({ type: 'booking.requested', booking: this.snapshot() });
  }

  /** Подтверждение тренером. Целевой статус выбирает PaymentDecision. */
  approve(actor: BookingActor, decision: PaymentDecision, now: Date): void {
    if (!(actor.kind === 'coach' && actor.id === this.s.trainerId)) throw BookingErrors.forbidden();
    if (this.s.status !== BookingStatus.AWAITING_COACH_APPROVAL) {
      throw BookingErrors.invalidTransition(this.s.status, BookingStatus.CONFIRMED);
    }
    this.apply(decision, now);
  }

  reject(actor: BookingActor, reason: CancellationReason | null, now: Date): void {
    if (!(actor.kind === 'coach' && actor.id === this.s.trainerId)) throw BookingErrors.forbidden();
    if (!reason) throw BookingErrors.reasonRequired();
    this.transition(BookingStatus.REJECTED_BY_COACH, now);
    this.s.cancellationReason = reason;
    this.record({ type: 'booking.rejected_by_coach', booking: this.snapshot() });
  }

  attachPayment(paymentId: string): void {
    this.s.paymentId = paymentId;
  }

  /** PaymentSucceeded — только по серверному webhook банка. Идемпотентно. */
  markPaid(paymentId: string, amount: Money, now: Date): void {
    if (this.s.status === BookingStatus.CONFIRMED && this.s.paymentId === paymentId) return;
    if ((this.s.paymentId !== null && this.s.paymentId !== paymentId) || !Money.equals(amount, this.s.price)) {
      throw BookingErrors.paymentMismatch();
    }
    this.transition(BookingStatus.CONFIRMED, now);
    this.s.paymentId = paymentId;
    this.record({ type: 'booking.confirmed', booking: this.snapshot() });
  }

  /** PaymentFailed / PaymentExpired. Повторная доставка — no-op. */
  paymentNotCompleted(now: Date): void {
    if (this.s.status !== BookingStatus.AWAITING_PAYMENT) return;
    this.expire(now);
  }

  cancel(actor: BookingActor, reason: CancellationReason | null, freeCancellationHours: number, now: Date): void {
    if (actor.kind === 'student' && actor.id === this.s.studentId) {
      const wasConfirmed = this.s.status === BookingStatus.CONFIRMED;
      this.transition(BookingStatus.CANCELLED_BY_STUDENT, now);
      const hoursLeft = (this.s.startsAt.getTime() - now.getTime()) / 3_600_000;
      this.s.lateCancellation = wasConfirmed && hoursLeft < freeCancellationHours;
      this.s.cancellationReason = reason;
      this.record({ type: 'booking.cancelled', booking: this.snapshot(), cancelledBy: 'STUDENT' });
    } else if (actor.kind === 'coach' && actor.id === this.s.trainerId) {
      if (!reason) throw BookingErrors.reasonRequired();
      this.transition(BookingStatus.CANCELLED_BY_COACH, now);
      this.s.cancellationReason = reason;
      this.record({ type: 'booking.cancelled', booking: this.snapshot(), cancelledBy: 'COACH' });
    } else {
      throw BookingErrors.forbidden();
    }
  }

  expire(now: Date): void {
    const previousStatus = this.s.status;
    this.transition(BookingStatus.EXPIRED, now);
    this.record({ type: 'booking.expired', booking: this.snapshot(), previousStatus });
  }

  complete(now: Date): void {
    if (now.getTime() < this.s.startsAt.getTime()) throw BookingErrors.invalidTransition(this.s.status, BookingStatus.COMPLETED);
    this.transition(BookingStatus.COMPLETED, now);
    this.record({ type: 'booking.completed', booking: this.snapshot() });
  }

  markNoShow(actor: BookingActor, now: Date): void {
    if (!(actor.kind === 'coach' && actor.id === this.s.trainerId)) throw BookingErrors.forbidden();
    if (now.getTime() < this.s.startsAt.getTime() + 15 * 60_000) {
      throw BookingErrors.invalidTransition(this.s.status, BookingStatus.NO_SHOW);
    }
    this.transition(BookingStatus.NO_SHOW, now);
    this.record({ type: 'booking.no_show', booking: this.snapshot() });
  }

  // ---------- Infrastructure helpers ----------

  snapshot(): BookingSnapshot {
    return { ...this.s };
  }

  /** Забрать накопленные доменные события (для записи в Outbox). */
  pullEvents(): BookingDomainEvent[] {
    const out = this.events;
    this.events = [];
    return out;
  }

  // ---------- Private ----------

  private apply(decision: PaymentDecision, now: Date): void {
    if (decision.kind === 'notRequired') {
      this.s.status = BookingStatus.CONFIRMED;
      this.s.paymentRequired = false;
    } else {
      this.s.status = BookingStatus.AWAITING_PAYMENT;
      this.s.paymentRequired = true;
      this.s.paymentDeadline = new Date(now.getTime() + decision.ttlSeconds * 1000);
    }
    this.s.updatedAt = now;
    this.s.version += 1;
    this.record({ type: 'booking.confirmed_by_coach', booking: this.snapshot(), paymentRequired: this.s.paymentRequired });
    if (this.s.status === BookingStatus.CONFIRMED) this.record({ type: 'booking.confirmed', booking: this.snapshot() });
  }

  private transition(next: BookingStatus, now: Date): void {
    if (!canTransition(this.s.status, next)) throw BookingErrors.invalidTransition(this.s.status, next);
    this.s.status = next;
    this.s.updatedAt = now;
    this.s.version += 1;
  }

  private record(e: BookingDomainEvent): void {
    this.events.push(e);
  }
}
