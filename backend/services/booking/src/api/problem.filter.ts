import { type ArgumentsHost, Catch, type ExceptionFilter, HttpException } from '@nestjs/common';
import { DomainProblem } from '@bitok/shared-kernel';
import type { Request, Response } from 'express';

/** Любая ошибка → application/problem+json (RFC 7807) с машинным кодом и traceId. */
@Catch()
export class ProblemFilter implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<Request>();
    const traceId = req.header('x-request-id') ?? undefined;
    let problem;
    if (error instanceof DomainProblem) {
      problem = error.toProblem(traceId);
    } else if (error instanceof HttpException) {
      const status = error.getStatus();
      problem = new DomainProblem(status, status === 400 ? 'BAD_REQUEST' : 'HTTP_ERROR', error.message).toProblem(traceId);
    } else {
      problem = new DomainProblem(500, 'INTERNAL_ERROR', 'Внутренняя ошибка').toProblem(traceId);
    }
    res.status(problem.status).type('application/problem+json').json(problem);
  }
}
