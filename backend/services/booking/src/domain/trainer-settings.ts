export interface TrainerBookingSettings {
  autoConfirm: boolean;
  minLeadTimeMinutes: number;
  freeCancellationHours: number;
  requiresPrepayment: boolean;
  lateCancellationRefundPercent: number;
}

export const DEFAULT_TRAINER_SETTINGS: TrainerBookingSettings = {
  autoConfirm: false,
  minLeadTimeMinutes: 120,
  freeCancellationHours: 12,
  requiresPrepayment: false,
  lateCancellationRefundPercent: 0,
};
