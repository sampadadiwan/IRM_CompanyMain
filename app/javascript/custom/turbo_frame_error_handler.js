/**
 * GLOBAL HANDLING FOR TURBO FRAME FAILURES
 *
 * Covers three failure modes that otherwise leave the user with a silent,
 * broken frame ("Content missing"):
 *
 * 1. Expired session: Devise redirects the frame request to the sign-in page,
 *    which has no matching <turbo-frame>. We detect the sign-in URL and promote
 *    the response to a full-page visit so the user lands on sign-in with the
 *    "session expired" flash visible.
 * 2. Genuine bug (response missing the frame for any other reason): we render a
 *    friendly retry card into the frame and log the details to the console so
 *    the bug stays visible to developers.
 * 3. Server (5xx) or network errors on frame requests: same retry card.
 *
 * The card markup lives in the layouts/_frame_error partial (a <template> in the
 * layout) so styling stays in SCSS and markup in ERB.
 */

// The <template> carries the sign-in path so the route is defined server-side;
// the literal here is only a fallback for layouts without the partial.
function errorTemplate() {
  return document.getElementById("turbo-frame-error-template")
}

function signInPath() {
  return errorTemplate()?.dataset?.signInPath || "/users/sign_in"
}

// True when the given response URL is the Devise sign-in page,
// i.e. the request was redirected because the session expired.
function isSignInUrl(url) {
  try {
    return new URL(url, window.location.origin).pathname === signInPath()
  } catch {
    return false
  }
}

// Replace the frame's contents with the friendly error card.
function renderErrorCard(frame) {
  const template = errorTemplate()
  if (!template) return // layout without the partial (e.g. devise pages) — keep default behavior

  frame.innerHTML = ""
  frame.appendChild(template.content.cloneNode(true))
}

// Shared failure path: keep the error loud for developers (the default Turbo
// error is suppressed once we preventDefault) and friendly for users.
function failFrame(frame, logMessage) {
  console.error(logMessage)
  renderErrorCard(frame)
}

// Resolve the <turbo-frame> a fetch event belongs to. The event fires on the
// initiating element: the frame itself for frame navigations, but the <form>
// or link for submissions — which may sit outside the frame it targets via
// data-turbo-frame.
function frameForFetchEvent(event) {
  const target = event.target
  if (!(target instanceof Element)) return null

  // closest() includes the element itself, covering frames and elements inside one
  const enclosing = target.closest("turbo-frame")
  if (enclosing) return enclosing

  const targetedId = target.getAttribute("data-turbo-frame")
  if (targetedId && targetedId !== "_top") return document.getElementById(targetedId)

  return null
}

// A frame response arrived without a matching <turbo-frame> element.
document.addEventListener("turbo:frame-missing", (event) => {
  const { response, visit } = event.detail

  if (isSignInUrl(response.url)) {
    // Session expired: break out of the frame and do a full page visit to
    // sign-in so the Devise flash ("Your session expired...") is shown.
    event.preventDefault()
    visit(response)
    return
  }

  // Genuine bug: response arrived but had no matching frame element.
  event.preventDefault()
  failFrame(
    event.target,
    `turbo:frame-missing — response from ${response.url} did not contain a ` +
    `<turbo-frame id="${event.target.id}"> element`
  )
})

// Belt-and-braces: raw 401s (e.g. turbo_stream requests Devise treats as
// non-navigational) mean the session is gone — do a full redirect to sign-in.
// Also catch 5xx responses to frame requests, which Turbo would ignore.
document.addEventListener("turbo:before-fetch-response", (event) => {
  const statusCode = event.detail.fetchResponse?.statusCode

  if (statusCode === 401) {
    event.preventDefault()
    window.location.assign(signInPath())
    return
  }

  const frame = frameForFetchEvent(event)
  if (statusCode >= 500 && frame) {
    event.preventDefault()
    failFrame(frame, `turbo frame request to ${event.detail.fetchResponse.location} failed with status ${statusCode}`)
  }
})

// Network-level failures (server unreachable, connection dropped) for frames.
document.addEventListener("turbo:fetch-request-error", (event) => {
  const frame = frameForFetchEvent(event)
  if (!frame) return

  event.preventDefault()
  failFrame(frame, `turbo frame request failed at the network level: ${event.detail?.error}`)
})

// Retry button inside the error card: reload the frame if it can be reloaded
// (has a src), otherwise fall back to a full page reload (e.g. frames that
// were populated by a form submission and have nothing to re-fetch).
document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-turbo-frame-error-retry]")
  if (!button) return

  event.preventDefault()
  const frame = button.closest("turbo-frame")
  if (frame?.src) {
    frame.reload()
  } else {
    window.location.reload()
  }
})
