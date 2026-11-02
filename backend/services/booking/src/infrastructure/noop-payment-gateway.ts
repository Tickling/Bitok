import { DomainProblem } from '@bitok/shared-kernel';
import type { PaymentGateway } from '../application/ports';

/** MVP-адаптер: оплата выключена. Подключение СБП = замена адаптера (PAYMENT_ADAPTER=grpc), ядро не меняется. */
export class NoopPaymentGateway implements PaymentGateway {
  private disabled(): never {
    throw new DomainProblem(503, 'FEATURE_DISABLED', 'Оплата пока недоступна');
  }
  async createSession(): Promise<never> {
    return this.disabled();
  }
  async cancelSession(): Promise<void> {}
  async requestRefund(): Promise<never> {
    return this.disabled();
  }
}
