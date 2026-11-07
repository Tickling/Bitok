/** Деньги в минимальных единицах (копейках) — без ошибок округления float. */
export interface Money {
  readonly amountMinor: number;
  readonly currency: 'RUB';
}

export const Money = {
  rubles(value: number): Money {
    return Money.of(Math.round(value * 100));
  },
  of(amountMinor: number): Money {
    if (!Number.isSafeInteger(amountMinor) || amountMinor < 0) {
      throw new RangeError(`Invalid money amount: ${amountMinor}`);
    }
    return { amountMinor, currency: 'RUB' };
  },
  zero: { amountMinor: 0, currency: 'RUB' } as Money,
  equals(a: Money, b: Money): boolean {
    return a.amountMinor === b.amountMinor && a.currency === b.currency;
  },
  /** Процент от суммы с округлением вниз до копейки (частичные возвраты). */
  percentage(m: Money, percent: number): Money {
    if (percent < 0 || percent > 100) throw new RangeError('percent must be 0..100');
    return Money.of(Math.floor((m.amountMinor * percent) / 100));
  },
};
