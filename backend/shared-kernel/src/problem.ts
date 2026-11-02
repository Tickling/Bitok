/** RFC 7807 Problem Details + машинный код ошибки (раздел 6.1 ANALYTICS.md). */
export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  code: string;
  detail?: string;
  traceId?: string;
  errors?: { field: string; message: string }[];
}

export class DomainProblem extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly title: string,
    readonly detail?: string,
  ) {
    super(`${code}: ${title}`);
    this.name = 'DomainProblem';
  }

  toProblem(traceId?: string): ProblemDetails {
    return {
      type: `https://docs.bitok.app/errors/${this.code.toLowerCase().replace(/_/g, '-')}`,
      title: this.title,
      status: this.status,
      code: this.code,
      ...(this.detail ? { detail: this.detail } : {}),
      ...(traceId ? { traceId } : {}),
    };
  }
}
