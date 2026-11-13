import { Body, Controller, Get, Headers, HttpCode, Inject, Param, Post, Put, Res } from '@nestjs/common';
import { DomainProblem } from '@bitok/shared-kernel';
import type { Response } from 'express';
import {
  ChangeBookingStatusHandler,
  CreateBookingHandler,
  type StatusAction,
} from '../application/handlers';
import type { BookingStore, Clock } from '../application/ports';
import type { Booking, BookingActor } from '../domain/booking';
import { BookingErrors } from '../domain/errors';
import { CLOCK, STORE } from './tokens';

/**
 * Контракт: api-contracts/openapi/booking.yaml.
 * Аутентификация выполняется на API Gateway: он проверяет JWT и пробрасывает X-User-Id / X-User-Role.
 */
@Controller('v1')
export class BookingsController {
  constructor(
    private readonly create: CreateBookingHandler,
    private readonly change: ChangeBookingStatusHandler,
    @Inject(STORE) private readonly store: BookingStore,
    @Inject(CLOCK) private readonly clock: Clock,
  ) {}

  @Post('bookings')
  @HttpCode(201)
  async createBooking(
    @Headers('x-user-id') userId: string | undefined,
    @Headers('idempotency-key') key: string | undefined,
    @Body() body: { slotId?: string; comment?: string; mode?: 'REQUEST' | 'DRAFT' },
    @Res({ passthrough: true }) res: Response,
  ) {
    const actor = this.actor(userId, 'STUDENT');
    if (!key) throw new DomainProblem(428, 'PRECONDITION_REQUIRED', 'Нужен заголовок Idempotency-Key');
    if (!body?.slotId) throw new DomainProblem(400, 'BAD_REQUEST', 'slotId обязателен');
    const { booking, replayed } = await this.create.execute({
      studentId: actor.id,
      slotId: body.slotId,
      comment: body.comment ?? null,
      idempotencyKey: key,
      mode: body.mode ?? 'REQUEST',
    });
    res.setHeader('ETag', `"${booking.version}"`);
    res.setHeader('Location', `/v1/bookings/${booking.id}`);
    res.setHeader('Idempotent-Replayed', String(replayed));
    return this.toDto(booking, actor);
  }

  @Get('bookings/:id')
  async getBooking(
    @Headers('x-user-id') userId: string | undefined,
    @Headers('x-user-role') role: string | undefined,
    @Param('id') id: string,
    @Res({ passthrough: true }) res: Response,
  ) {
    const actor = this.actor(userId, role);
    const booking = await this.store.transaction((tx) => tx.getBooking(id));
    if (!booking) throw BookingErrors.notFound('Бронирование');
    if (actor.id !== booking.studentId && actor.id !== booking.trainerId) throw BookingErrors.forbidden();
    res.setHeader('ETag', `"${booking.version}"`);
    return this.toDto(booking, actor);
  }

  @Put('bookings/:id/status')
  async changeStatus(
    @Headers('x-user-id') userId: string | undefined,
    @Headers('x-user-role') role: string | undefined,
    @Headers('if-match') ifMatch: string | undefined,
    @Param('id') id: string,
    @Body() body: StatusAction,
    @Res({ passthrough: true }) res: Response,
  ) {
    const actor = this.actor(userId, role);
    if (!ifMatch) throw new DomainProblem(428, 'PRECONDITION_REQUIRED', 'Нужен заголовок If-Match');
    const version = Number(ifMatch.replace(/"/g, ''));
    const booking = await this.change.execute(id, actor, body, version);
    res.setHeader('ETag', `"${booking.version}"`);
    return this.toDto(booking, actor);
  }

  private actor(userId: string | undefined, role: string | undefined): BookingActor & { id: string } {
    if (!userId) throw new DomainProblem(401, 'UNAUTHORIZED', 'Требуется авторизация');
    return role === 'TRAINER' ? { kind: 'coach', id: userId } : { kind: 'student', id: userId };
  }

  /** DTO по схеме Booking из OpenAPI; allowedActions — сервер решает, что доступно в UI. */
  private toDto(booking: Booking, actor: BookingActor) {
    const s = booking.snapshot();
    return {
      id: s.id,
      slotId: s.slotId,
      studentId: s.studentId,
      trainerId: s.trainerId,
      initiatedBy: s.initiatedBy,
      startsAt: s.startsAt.toISOString(),
      durationMinutes: s.durationMinutes,
      price: s.price,
      status: s.status,
      paymentRequired: s.paymentRequired,
      ...(s.paymentRequired && s.paymentDeadline ? { payment: { paymentId: s.paymentId, paymentDeadline: s.paymentDeadline.toISOString() } } : {}),
      approvalExpiresAt: booking.status === 'AWAITING_COACH_APPROVAL' ? booking.approvalExpiresAt.toISOString() : null,
      draftExpiresAt: s.draftExpiresAt?.toISOString() ?? null,
      comment: s.comment,
      cancellationReason: s.cancellationReason ?? undefined,
      lateCancellation: s.lateCancellation,
      rescheduleCount: s.rescheduleCount,
      createdAt: s.createdAt.toISOString(),
      updatedAt: s.updatedAt.toISOString(),
      version: s.version,
      allowedActions: booking.allowedActions(actor, this.clock.now()),
    };
  }
}
