// Locale-aware date formatting for JS-rendered UI (ag-Grid cells, etc.).
//
// The server resolves the active locale from the Accept-Language header
// (WithLocale#set_locale) and publishes that locale's `date.formats.default` /
// `time.formats.default` strftime pattern as a meta tag in the layout head
// (layouts/_locale_date_meta.html.erb). Reading it here keeps grid cells
// consistent with every Rails-rendered date on the same page (%d/%m/%Y for :en,
// %m/%d/%Y for :en-US, %Y/%m/%d for :ja).
//
// Do NOT reach for a JS date library instead — there isn't one, deliberately.
// The ag-Grid date bug this module replaced came from moment's `format('L')`:
// the importmap pinned the bare moment build, which ships the `en` locale only,
// so `.locale('en-GB')` silently no-opped and every user got MM/DD/YYYY.

function metaContent(name) {
  const el = document.querySelector(`meta[name="${name}"]`);
  const content = el && el.content && el.content.trim();
  return content || null;
}

// The patterns are fixed for the life of a page load (the locale comes from a
// request header), so cache rather than hitting the DOM once per rendered cell.
// Turbo can swap the <head> on navigation, hence the reset.
let cache = {};
document.addEventListener("turbo:load", () => { cache = {}; });

function cachedMeta(name) {
  if (!(name in cache)) cache[name] = metaContent(name);
  return cache[name];
}

// Returns the active locale's strftime pattern, or null when the layout does
// not publish one. Callers must handle null rather than assume a format.
export function appDateFormat() {
  return cachedMeta("app-date-format");
}

export function appTimeFormat() {
  return cachedMeta("app-time-format");
}

function pad(n) {
  return String(n).padStart(2, "0");
}

const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MONTHS_LONG  = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"];
const DAYS_SHORT   = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const DAYS_LONG    = ["Sunday", "Monday", "Tuesday", "Wednesday",
                      "Thursday", "Friday", "Saturday"];

const TOKENS = {
  "%d":  (d) => pad(d.getDate()),
  "%-d": (d) => String(d.getDate()),
  "%e":  (d) => String(d.getDate()),
  "%m":  (d) => pad(d.getMonth() + 1),
  "%-m": (d) => String(d.getMonth() + 1),
  "%Y":  (d) => String(d.getFullYear()),
  "%y":  (d) => pad(d.getFullYear() % 100),
  "%b":  (d) => MONTHS_SHORT[d.getMonth()],
  "%B":  (d) => MONTHS_LONG[d.getMonth()],
  "%a":  (d) => DAYS_SHORT[d.getDay()],
  "%A":  (d) => DAYS_LONG[d.getDay()],
  "%H":  (d) => pad(d.getHours()),
  "%I":  (d) => pad(d.getHours() % 12 || 12),
  "%M":  (d) => pad(d.getMinutes()),
  "%S":  (d) => pad(d.getSeconds()),
  "%p":  (d) => (d.getHours() < 12 ? "AM" : "PM")
};

// Renders a Date using a Ruby strftime pattern. Only the tokens that appear in
// config/locales/*.yml date/time formats are supported; the regex matches a
// whole token and looks it up exactly, so an unsupported one is left in place
// and shows up as visible text rather than silently rendering something wrong.
export function strftime(date, format) {
  return format.replace(/%-?[a-zA-Z]/g, (token) => {
    const fn = TOKENS[token];
    return fn ? fn(date) : token;
  });
}

// Parses the values that reach a grid cell: ISO strings ("2026-08-19",
// "2026-08-19T10:30:00Z"), Ruby Time#to_s ("2026-08-19 10:30:00 +0530"),
// Date objects and epoch millis. Returns null when the value is not a date.
// Always returns a NEW Date — callers such as the ag-Grid filter comparator
// normalise the time component, which would otherwise mutate the row data.
export function parseDate(value) {
  if (value === null || value === undefined || value === "") return null;
  if (value instanceof Date) {
    return isNaN(value.getTime()) ? null : new Date(value.getTime());
  }
  if (typeof value === "number") {
    const d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }

  const raw = String(value).trim();
  // A date-only string must be read as local midnight, not UTC midnight, or a
  // negative-offset browser renders the previous day.
  const dateOnly = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (dateOnly) {
    return new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3]));
  }
  // "2026-08-19 10:30:00 +0530" — Safari/Firefox reject the space-separated form.
  const rubyTime = raw.match(/^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})(.*)$/);
  if (rubyTime) {
    const d = new Date(`${rubyTime[1]}T${rubyTime[2]}${rubyTime[3].trim()}`);
    if (!isNaN(d.getTime())) return d;
  }

  const parsed = new Date(raw);
  return isNaN(parsed.getTime()) ? null : parsed;
}

// Fallback for a layout that publishes no meta tag. Guessing a fixed pattern
// here would reintroduce exactly the silent wrong-format failure this module
// exists to remove, so defer to the browser's own locale — Intl, unlike the
// moment build this replaced, actually honours it.
const BROWSER_DATE_OPTS = { year: "numeric", month: "2-digit", day: "2-digit" };
const BROWSER_TIME_OPTS = { ...BROWSER_DATE_OPTS, hour: "2-digit", minute: "2-digit" };

// Formats a value in the active Rails locale's date format. `format` overrides
// it with an explicit strftime pattern. Returns "" for blank/unparseable input
// so a grid cell never shows "Invalid Date".
export function formatLocaleDate(value, format = null) {
  const date = parseDate(value);
  if (!date) return "";
  const pattern = format || appDateFormat();
  return pattern ? strftime(date, pattern)
                 : date.toLocaleDateString(undefined, BROWSER_DATE_OPTS);
}

export function formatLocaleDateTime(value, format = null) {
  const date = parseDate(value);
  if (!date) return "";
  const pattern = format || appTimeFormat();
  return pattern ? strftime(date, pattern)
                 : date.toLocaleString(undefined, BROWSER_TIME_OPTS);
}

// Human-readable rendering of a strftime pattern ("%d/%m/%Y" -> "dd/mm/yyyy"),
// for placeholders and tooltips that tell the user what to type.
export function dateFormatHint(format = null) {
  const pattern = format || appDateFormat();
  if (!pattern) return "";
  return pattern.replace("%d", "dd").replace("%m", "mm").replace("%Y", "yyyy");
}

// Reads a date the USER TYPED, in the active locale's format, and returns ISO
// "YYYY-MM-DD" (or null). This is the inverse of formatLocaleDate and the one
// place typed dates are interpreted — the locale-date Stimulus controller and
// the ag-Grid column filter both go through it so a date typed into a filter
// means the same thing as a date typed into a form.
//
// ISO input is accepted too, so a Capybara `fill_in` and a value round-tripped
// from the server both work regardless of the active locale.
export function parseLocaleDate(value, format = null) {
  if (value === null || value === undefined) return null;
  const raw = String(value).trim();
  if (!raw) return null;

  // Ruby Time#to_s / ActiveSupport datetime prefix, or an exact ISO date
  const isoPrefix = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoPrefix) return validIsoDate(`${isoPrefix[1]}-${isoPrefix[2]}-${isoPrefix[3]}`);

  const pattern = format || appDateFormat();
  if (!pattern) return null;

  // Positional order of the day/month/year tokens within the locale's pattern
  const tokens = [
    { key: "d", pos: pattern.indexOf("%d") },
    { key: "m", pos: pattern.indexOf("%m") },
    { key: "y", pos: pattern.indexOf("%Y") }
  ];
  // A pattern missing any of the three can't be read back positionally — bail out
  // rather than mapping capture groups onto the wrong parts.
  if (tokens.some((t) => t.pos === -1)) return null;
  const order = tokens.sort((a, b) => a.pos - b.pos).map((t) => t.key);

  // Escape regex metacharacters in the separators (e.g. the '.' in %d.%m.%Y)
  // before substituting the capture groups.
  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const strict = escaped
    .replace("%d", "(\\d{1,2})")
    .replace("%m", "(\\d{1,2})")
    .replace("%Y", "(\\d{4})");

  let match = raw.match(new RegExp("^" + strict + "$"));
  // Fall back to a separator-agnostic read in the same token order, so "1-2-2026"
  // and "1.2.2026" work under a %d/%m/%Y locale. Only the punctuation is relaxed;
  // the day/month/year order is still the locale's.
  if (!match) match = raw.match(/^(\d{1,4})[\/\-. ](\d{1,2})[\/\-. ](\d{1,4})$/);
  if (!match) return null;

  const parts = {};
  order.forEach((key, i) => { parts[key] = match[i + 1].padStart(2, "0"); });
  if (parts.y.length !== 4) return null;
  return validIsoDate(`${parts.y}-${parts.m}-${parts.d}`);
}

// Returns the ISO string only if it denotes a real calendar date, so an
// impossible date such as "31/02/2026" is rejected rather than silently
// rolling over into March and filtering on a day the user never asked for.
function validIsoDate(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  const date = new Date(Date.UTC(y, m - 1, d));
  const roundTrips = date.getUTCFullYear() === y &&
                     date.getUTCMonth() === m - 1 &&
                     date.getUTCDate() === d;
  return roundTrips ? iso : null;
}
