// Import and register all your controllers from the importmap under controllers/*

import { application } from "controllers/application"

// Lazy load controllers as they appear in the DOM: a page imports only the controllers its
// data-controller attributes name, and a MutationObserver picks up ones added later (Turbo
// frames/streams, modals, cocoon rows). Eager loading imported all ~200 controllers - and the
// libraries they pull in - on every full page load. The import map pins controllers with
// preload: false (config/importmap.rb) so the browser doesn't fetch them all anyway.
// Consequence for controller code: another controller on the page may not be loaded yet when
// yours connects, so treat getControllerForElementAndIdentifier(...) as possibly null.
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)

import { isFadeFrame, enterFadeFrames, settleFadeFrames, FADED_IN_ATTR } from "custom/frame_fade_in"

// ── Tab frames fade in (ported from the subtle_ui branch) ─────────────────────
// Fade frames (custom/frame_fade_in.js: `.frame-fade-in`, and every turbo-frame inside a tab pane)
// get pushed into their hidden `--entering` state here, *before* Turbo swaps in the new content -
// not after. Hiding it after turbo:frame-load let the browser paint the fully-visible new content
// for a frame first, which read as a flicker (appear, disappear, then slide in).
// Only a frame's first load fades: a frame already showing content (FADED_IN_ATTR) is re-rendered in
// place, so search/pagination and broadcast reloads don't blink the whole frame out and back in.
document.documentElement.addEventListener('turbo:before-frame-render', function (e) {
    if (isFadeFrame(e.target) && !e.target.hasAttribute(FADED_IN_ATTR)) {
        e.target.classList.add('frame-fade-in--entering');
    }
});

//This is required to ensure that forms loaded via turbo have the ClientSideValidations turned on.
document.documentElement.addEventListener('turbo:frame-load', function (e) {
    // console.log($(e.target).find('form'));
    if($(e.target).find('form').length > 0) {
        $(e.target).find('form').enableClientSideValidations();
    }

    // Now that the new content is in and still hidden, drop back to the default (visible) state so
    // the CSS transition animates it in - straight away, not after a hold: the frame was showing its
    // loading spinner until before-frame-render hid it, so a hold only added a blank beat between
    // spinner and content. Turbo already repaints between before-frame-render and frame-load, so the
    // hidden state is on screen; reading offsetWidth just guarantees it is applied before the class
    // comes off, so the transition always starts from opacity 0.
    if (isFadeFrame(e.target)) {
        e.target.setAttribute(FADED_IN_ATTR, '');
        if (e.target.classList.contains('frame-fade-in--entering')) {
            void e.target.offsetWidth;
            e.target.classList.remove('frame-fade-in--entering');
        }
    }
});

// The turbo:* listeners above only fire the first time a frame's `src` is fetched. After that,
// switching back to an already-loaded tab is just Bootstrap toggling `.tab-pane` visibility - no
// Turbo event fires - so these listen to Bootstrap's own tab-switch events to replay the
// transition every time a tab is opened, loaded or not. Works for screens picked from a dropdown
// tab (layouts/_dropdown_tab) too: their menu rows carry the same href="#pane".
function resolveTabPane(e) {
    var targetSelector = e.target.getAttribute('href') || e.target.getAttribute('data-bs-target');
    return targetSelector && targetSelector.startsWith('#') && document.querySelector(targetSelector);
}

document.documentElement.addEventListener('show.bs.tab', function (e) {
    var pane = resolveTabPane(e);
    if (pane) enterFadeFrames(pane);
});

document.documentElement.addEventListener('shown.bs.tab', function (e) {
    var pane = resolveTabPane(e);
    if (pane) settleFadeFrames(pane);
});

// ── Opening a tab scrolls its tab bar to the top (ported from the subtle_ui branch) ──
// The newly revealed pane gets the full viewport instead of starting below the record header and
// action buttons. Applies to every tab bar except ones inside a modal/offcanvas, which manage
// their own viewport.
//
// Most panes hold a lazy turbo-frame still fetching when 'shown.bs.tab' fires, so the pane is just
// a spinner, the document is temporarily short, and the scroll clamps above the target. So the
// scroll runs at 'shown' for immediate feedback, and again on each 'turbo:frame-load' in that pane
// once real content has given the page its full height - until the user takes over or 8s pass.
// The re-alignment uses behavior 'auto', which follows the CSS scroll-behavior - smooth under the
// modernize theme (:root, unless the user prefers reduced motion), instant elsewhere. It starts in
// the same frame the new content starts fading in from opacity 0, and only when the tab bar has
// drifted, so it is one short correction rather than a lurch per frame load.
var pendingTabScroll = null; // { nav: Element, pane: Element|null, deadline: epoch ms }

// The theme's header.topbar is position:fixed, so "top of the window" means just below it -
// measured live rather than hard-coding its height, plus 8px breathing room
function topbarOffset() {
    var topbar = document.querySelector('header.topbar');
    return (topbar ? topbar.offsetHeight : 0) + 8;
}

function scrollTabBarToTop(nav, behavior) {
    var top = Math.max(nav.getBoundingClientRect().top + window.scrollY - topbarOffset(), 0);
    // Already in place (within a few px) - don't nudge the page for nothing
    if (Math.abs(top - window.scrollY) <= 4) return;
    window.scrollTo({ top: top, behavior: behavior || 'smooth' });
}

// Keep the page tall enough for the tab bar to reach the top while the incoming pane is shown.
// Without it, leaving a long pane for one still loading shrank the page to a spinner: the browser
// clamped the scroll (one jump), the scroll below stopped short, and the rows arriving forced a
// second scroll. With the pane at least this tall, the single scroll at 'shown' lands on target and
// the re-align on frame-load finds nothing to correct. It stays while the pane is shown, so a short
// pane (an empty grid) doesn't shrink the page after loading and clamp it again.
document.documentElement.addEventListener('show.bs.tab', function (e) {
    if (e.target.closest('.modal, .offcanvas')) return;
    var nav = e.target.closest('.nav, [role="tablist"]');
    var pane = resolveTabPane(e);
    // The incoming pane is still display:none here, so measure where it will sit from its container
    if (!nav || !pane || !pane.parentElement) return;
    var gap = pane.parentElement.getBoundingClientRect().top - nav.getBoundingClientRect().top;
    pane.style.minHeight = Math.max(window.innerHeight - topbarOffset() - gap, 0) + 'px';
});

document.documentElement.addEventListener('shown.bs.tab', function (e) {
    if (e.target.closest('.modal, .offcanvas')) return;
    // A dropdown tab's screen sits in a .dropdown-menu inside the bar, so this finds the bar itself
    var nav = e.target.closest('.nav, [role="tablist"]');
    if (!nav) return;
    scrollTabBarToTop(nav);
    pendingTabScroll = { nav: nav, pane: resolveTabPane(e), deadline: Date.now() + 8000 };
});

// Any scroll input from the user (wheel, touch, keys, scrollbar drag or a click) means they've
// taken over - stop re-aligning under them
['wheel', 'touchmove', 'keydown', 'mousedown'].forEach(function (evt) {
    window.addEventListener(evt, function () { pendingTabScroll = null; }, { passive: true });
});

function realignPendingTabScroll(e) {
    if (!pendingTabScroll) return;
    // Frames loading elsewhere on the page (another pane, the header) don't move the page
    if (pendingTabScroll.pane && !pendingTabScroll.pane.contains(e.target)) return;
    if (Date.now() > pendingTabScroll.deadline || !document.contains(pendingTabScroll.nav)) {
        pendingTabScroll = null;
        return;
    }
    scrollTabBarToTop(pendingTabScroll.nav, 'auto');
}

document.documentElement.addEventListener('turbo:frame-load', realignPendingTabScroll);

// app/javascript/application.js
// addEventListener("turbo:before-frame-render", (event) => {
//     if (document.startViewTransition) {
//       const originalRender = event.detail.render
//       event.detail.render = (currentElement, newElement) => {
//         document.startViewTransition(()=> originalRender(currentElement, newElement))
//       }
//     }
// })

