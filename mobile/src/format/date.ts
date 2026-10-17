/**
 * Dates in the signed-in user's locale format — the SAME strftime pattern the website uses
 * (`date.formats.default` from GET /api/mobile/v1/me: `%d/%m/%Y` for India English,
 * `%m/%d/%Y` for US English). The app speaks strftime, as the website's
 * app/javascript/custom/locale_date_format.js does; there is no date library.
 */
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December'];

let datePattern = '%d/%m/%Y';
let timePattern = '%d/%m/%Y %H:%M';

/** Set once from /me after sign-in */
export function setDateFormats(date?: string | null, time?: string | null) {
  if (date) datePattern = date;
  if (time) timePattern = time;
}

/** Parses "2026-10-30" as a calendar date (no timezone shift) or any ISO timestamp */
export function parseDate(value: string | Date | null | undefined): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  const ymd = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (ymd) return new Date(Number(ymd[1]), Number(ymd[2]) - 1, Number(ymd[3]));
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

const pad = (n: number) => String(n).padStart(2, '0');

export function strftime(date: Date, pattern: string): string {
  return pattern.replace(/%([dmYyBbHMe%])/g, (_, code: string) => {
    switch (code) {
      case 'd': return pad(date.getDate());
      case 'e': return String(date.getDate());
      case 'm': return pad(date.getMonth() + 1);
      case 'Y': return String(date.getFullYear());
      case 'y': return pad(date.getFullYear() % 100);
      case 'B': return MONTHS[date.getMonth()];
      case 'b': return MONTHS[date.getMonth()].slice(0, 3);
      case 'H': return pad(date.getHours());
      case 'M': return pad(date.getMinutes());
      default: return '%';
    }
  });
}

/** 30/10/2026 for India English */
export function formatDate(value: string | Date | null | undefined): string {
  const date = parseDate(value);
  return date ? strftime(date, datePattern) : '';
}

export function formatDateTime(value: string | Date | null | undefined): string {
  const date = parseDate(value);
  return date ? strftime(date, timePattern) : '';
}

/** "Today", "Yesterday" or the date — for alert lists */
export function formatRelativeDay(value: string | Date | null | undefined): string {
  const date = parseDate(value);
  if (!date) return '';
  const today = new Date();
  const startOf = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((startOf(today) - startOf(date)) / 86_400_000);
  if (days === 0) return `Today ${strftime(date, '%H:%M')}`;
  if (days === 1) return 'Yesterday';
  return formatDate(date);
}
