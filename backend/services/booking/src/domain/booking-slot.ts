import type { Money } from '@bitok/shared-kernel';
import { BookingErrors } from './errors';

export type SlotStatus = 'AVAILABLE' | 'HELD' | 'BOOKED' | 'BLOCKED' | 'CANCELLED';

export interface BookingSlotProps {
  id: string;
  trainerId: string;
  clubId: string;
  startsAt: Date;
  durationMinutes: number;
  price: Money;
  status: SlotStatus;
  heldUntil: Date | null;
  version: number;
}

export class BookingSlot {
  private constructor(private props: BookingSlotProps) {}

  static create(p: Omit<BookingSlotProps, 'status' | 'heldUntil' | 'version'>): BookingSlot {
    if (p.durationMinutes < 30 || p.durationMinutes > 180 || p.durationMinutes % 15 !== 0) {
      throw new RangeError('durationMinutes must be 30..180 with 15-minute step');
    }
    return new BookingSlot({ ...p, status: 'AVAILABLE', heldUntil: null, version: 0 });
  }

  static restore(p: BookingSlotProps): BookingSlot {
    return new BookingSlot({ ...p });
  }

  get id() { return this.props.id; }
  get trainerId() { return this.props.trainerId; }
  get clubId() { return this.props.clubId; }
  get startsAt() { return this.props.startsAt; }
  get durationMinutes() { return this.props.durationMinutes; }
  get price() { return this.props.price; }
  get status() { return this.props.status; }
  get heldUntil() { return this.props.heldUntil; }
  get version() { return this.props.version; }
  get endsAt(): Date { return new Date(this.startsAt.getTime() + this.durationMinutes * 60_000); }

  /** Свободен или холд истёк (ленивое истечение — не ждём планировщик). */
  isBookable(now: Date): boolean {
    if (this.props.status === 'AVAILABLE') return true;
    return this.props.status === 'HELD' && (this.props.heldUntil?.getTime() ?? 0) <= now.getTime();
  }

  hold(until: Date, now: Date): void {
    if (!this.isBookable(now)) throw BookingErrors.slotAlreadyTaken();
    this.props = { ...this.props, status: 'HELD', heldUntil: until, version: this.props.version + 1 };
  }

  /**
   * Переустановить срок холда при смене этапа брони (заявка → оплата): срок ЗАМЕНЯЕТСЯ, а не расширяется.
   * При оплате это paymentDeadline + grace — холд всегда переживает платёжную сессию (BR-020.1),
   * но неоплаченный слот не блокируется дольше нужного.
   */
  resetHold(until: Date): void {
    if (this.props.status !== 'HELD') return;
    this.props = { ...this.props, heldUntil: until, version: this.props.version + 1 };
  }

  markBooked(): void {
    this.props = { ...this.props, status: 'BOOKED', heldUntil: null, version: this.props.version + 1 };
  }

  release(): void {
    if (this.props.status !== 'HELD' && this.props.status !== 'BOOKED') return;
    this.props = { ...this.props, status: 'AVAILABLE', heldUntil: null, version: this.props.version + 1 };
  }

  snapshot(): BookingSlotProps {
    return { ...this.props };
  }
}
