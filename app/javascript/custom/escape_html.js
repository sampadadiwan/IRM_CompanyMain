// M17 / L16 (OWASP 2026-11) — HTML-escape a value before it is put into an HTML string (a template literal that
// becomes innerHTML or an ag-Grid cell). Names, tags and labels are typed by users, so "<img src=x onerror=…>" as an
// investor name used to run in every colleague's browser. Escaping changes nothing a normal name shows.
// Also safe inside double-quoted attributes (", ' and ` are escaped).
//
// @param {*} value — anything; null / undefined become ""
// @returns {string}
export function escapeHtml(value) {
  if (value === null || value === undefined) return ""
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/`/g, "&#96;")
}

// A URL for an href/src attribute: only http(s), mailto, relative and data:image URLs pass; anything else
// (javascript:, vbscript:, data:text/html …) becomes "" so the attribute is inert. The result is also escaped.
// @param {*} value
// @returns {string}
export function safeUrl(value) {
  const url = String(value ?? "").trim()
  if (url === "") return ""
  const ok = /^(https?:|mailto:|\/(?!\/)|\.{0,2}\/|#|data:image\/)/i.test(url) || !/^[a-z][a-z0-9+.-]*:/i.test(url)
  return ok ? escapeHtml(url) : ""
}
