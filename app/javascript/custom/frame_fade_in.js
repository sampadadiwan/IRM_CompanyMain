// Ported from the subtle_ui branch. Shared by controllers/index.js (Bootstrap-driven tabs) and
// offcanvastabs_controller.js (the one place using a custom tab mechanism instead of Bootstrap's)
// to replay the fade frames' slide-and-fade on every tab switch, not just a frame's first load.
// See custom/frame_fade_in.scss for the CSS side of this.

// Which frames fade: any frame opted in with the `frame-fade-in` class, plus every turbo-frame
// inside a tab pane - so detail-page tabs get the effect without each view opting in
export const FADE_FRAME_SELECTOR = '.frame-fade-in, .tab-pane turbo-frame';

export function isFadeFrame(el) {
  return !!(el && el.matches && el.matches(FADE_FRAME_SELECTOR));
}

// Set on a frame once its first load has faded in, so later reloads (search, pagination,
// broadcast reloads) swap in place instead of blinking out and fading in again
export const FADED_IN_ATTR = 'data-frame-faded-in';

// A frame still waiting on its first response (lazy src, no Turbo `complete` yet) is left visible
// so its loading spinner shows; turbo:before-frame-render hides it just before the content lands.
// Hiding it here too gave it two reveals (spinner fades in, vanishes, content fades in).
function hasContent(frame) {
  return !frame.hasAttribute('src') || frame.hasAttribute('complete');
}

// Push a pane's loaded fade frames into their hidden, offset `--entering` state
export function enterFadeFrames(root) {
  root.querySelectorAll(FADE_FRAME_SELECTOR).forEach(function (frame) {
    if (hasContent(frame)) frame.classList.add('frame-fade-in--entering');
  });
}

// A deliberate hold in the hidden state before releasing into the reveal. Entering is an instant
// jump (`transition: none` on --entering in frame_fade_in.scss), so the hold just guarantees the
// hidden state is committed and painted before the class comes off, and gives the swap a beat to
// settle so the reveal reads as one deliberate motion rather than a twitch.
export const SETTLE_HOLD_MS = 250;

// Release a pane's fade frames so the CSS transition animates them in
export function settleFadeFrames(root) {
  setTimeout(function () {
    root.querySelectorAll(FADE_FRAME_SELECTOR).forEach(function (frame) {
      frame.classList.remove('frame-fade-in--entering');
    });
  }, SETTLE_HOLD_MS);
}
