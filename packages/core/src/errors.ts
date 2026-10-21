// Application error codes raised by app.* functions (see migration 0200). Clients map SQLSTATE to these.

export const DOMAIN_ERRORS = {
  SOL01: 'insufficient_stock',
  SOL02: 'idempotency_conflict',
  SOL03: 'forbidden',
  SOL04: 'invalid_state',
  SOL05: 'validation_failed',
  SOL06: 'ledger_invariant_violated',
} as const;

export type DomainErrorCode = (typeof DOMAIN_ERRORS)[keyof typeof DOMAIN_ERRORS];

export class DomainError extends Error {
  readonly code: DomainErrorCode | 'unexpected';
  readonly sqlstate: string | undefined;

  constructor(code: DomainErrorCode | 'unexpected', message: string, sqlstate?: string) {
    super(message);
    this.name = 'DomainError';
    this.code = code;
    this.sqlstate = sqlstate;
  }
}

export function domainCodeFor(sqlstate: string | undefined): DomainErrorCode | 'unexpected' {
  if (sqlstate !== undefined && sqlstate in DOMAIN_ERRORS) {
    return DOMAIN_ERRORS[sqlstate as keyof typeof DOMAIN_ERRORS];
  }
  return 'unexpected';
}
