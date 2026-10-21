// Money is integer kobo (bigint) everywhere. No floats, ever. Across JSON, kobo travels as a string.

declare const koboBrand: unique symbol;
export type Kobo = bigint & { readonly [koboBrand]: true };

const INTEGER = /^-?\d+$/;

/** Accepts a bigint or a canonical integer string (as returned by Postgres/JSON). */
export function kobo(value: bigint | string): Kobo {
  if (typeof value === 'bigint') return value as Kobo;
  if (!INTEGER.test(value)) throw new RangeError(`not an integer kobo amount: ${JSON.stringify(value)}`);
  return BigInt(value) as Kobo;
}

/** Serialise for JSON / RPC parameters. */
export function koboToString(value: Kobo): string {
  return value.toString();
}

const NAIRA_INPUT = /^(-)?(\d{1,3}(,\d{3})*|\d+)(\.(\d{1,2}))?$/;

/** Parses user input like "1,234.5" or "1234.56" into kobo exactly. More than 2 decimals is an error. */
export function nairaToKobo(input: string): Kobo {
  const m = NAIRA_INPUT.exec(input.trim());
  if (!m) throw new RangeError(`not a naira amount with at most 2 decimals: ${JSON.stringify(input)}`);
  const whole = BigInt((m[2] ?? '0').replaceAll(',', ''));
  const fraction = BigInt((m[5] ?? '').padEnd(2, '0') || '0');
  const value = whole * 100n + fraction;
  return (m[1] ? -value : value) as Kobo;
}

/** "₦1,234.56" / "-₦0.05". Pure bigint arithmetic. */
export function formatNaira(value: Kobo): string {
  const negative = value < 0n;
  const abs = negative ? -value : value;
  const whole = (abs / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const fraction = (abs % 100n).toString().padStart(2, '0');
  return `${negative ? '-' : ''}₦${whole}.${fraction}`;
}
