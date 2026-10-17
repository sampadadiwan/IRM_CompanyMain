/**
 * Money as the app shows it (proposal principle 11, spec "Display formats").
 *
 * The server sends `{ amount: "7500000.00", currency: "INR" }` (or, from the website's own JSON
 * endpoints, a plain number in the fund's currency). Exact amounts use the currency's grouping —
 * lakh/crore for INR (₹5,00,00,000) — and cards use compact amounts (₹5.00 Cr, $1.2M).
 */
export type Money = { amount: string; currency: string };

const LOCALE_FOR: Record<string, string> = { INR: 'en-IN' };

function toNumber(value: Money | number | string | null | undefined): number {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Number(value) || 0;
  return Number(value.amount) || 0;
}

/** ₹5,00,00,000 · $1,250,000.00 — exact, for detail screens */
export function formatMoney(value: Money | number | null | undefined, currency?: string): string {
  const code = currency ?? (value && typeof value === 'object' ? value.currency : undefined) ?? 'INR';
  const amount = toNumber(value);
  const whole = Number.isInteger(amount);
  return new Intl.NumberFormat(LOCALE_FOR[code] ?? 'en-US', {
    style: 'currency',
    currency: code,
    minimumFractionDigits: whole ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

/** ₹5.00 Cr · ₹75.00 L · $1.2M — compact, for cards */
export function formatMoneyCompact(value: Money | number | null | undefined, currency?: string): string {
  const code = currency ?? (value && typeof value === 'object' ? value.currency : undefined) ?? 'INR';
  const amount = toNumber(value);
  const symbol = currencySymbol(code);
  const abs = Math.abs(amount);
  const sign = amount < 0 ? '-' : '';

  if (code === 'INR') {
    if (abs >= 1e7) return `${sign}${symbol}${(abs / 1e7).toFixed(2)} Cr`;
    if (abs >= 1e5) return `${sign}${symbol}${(abs / 1e5).toFixed(2)} L`;
    return formatMoney(amount, code);
  }
  if (abs >= 1e9) return `${sign}${symbol}${(abs / 1e9).toFixed(1)}B`;
  if (abs >= 1e6) return `${sign}${symbol}${(abs / 1e6).toFixed(1)}M`;
  if (abs >= 1e4) return `${sign}${symbol}${(abs / 1e3).toFixed(0)}K`;
  return formatMoney(amount, code);
}

export function currencySymbol(code: string): string {
  const parts = new Intl.NumberFormat(LOCALE_FOR[code] ?? 'en-US', { style: 'currency', currency: code })
    .formatToParts(0);
  return parts.find((p) => p.type === 'currency')?.value ?? `${code} `;
}

export function moneyNumber(value: Money | number | string | null | undefined): number {
  return toNumber(value);
}

/** "₹3.20 Cr" split into figure and unit, for the big-number tiles: { value: '₹3.20', unit: 'Cr' } */
export function moneyParts(value: Money | number | null | undefined, currency?: string): { value: string; unit: string } {
  const compact = formatMoneyCompact(value, currency);
  const match = /^(.*?)\s?(Cr|L|K|M|B)$/.exec(compact);
  return match ? { value: match[1], unit: match[2] } : { value: compact, unit: '' };
}
