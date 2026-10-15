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

import { isFadeFrame, enterFadeFrames, settleFadeFrames, SETTLE_HOLD_MS } from "custom/frame_fade_in"

// ── Tab frames fade in (ported from the subtle_ui branch) ─────────────────────
// Fade frames (custom/frame_fade_in.js: `.frame-fade-in`, and every turbo-frame inside a tab pane)
// get pushed into their hidden `--entering` state here, *before* Turbo swaps in the new content -
// not after. Hiding it after turbo:frame-load let the browser paint the fully-visible new content
// for a frame first, which read as a flicker (appear, disappear, then slide in).
document.documentElement.addEventListener('turbo:before-frame-render', function (e) {
    if (isFadeFrame(e.target)) {
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
    // the CSS transition animates it in, after a deliberate hold (SETTLE_HOLD_MS)
    if (isFadeFrame(e.target)) {
        setTimeout(function () {
            e.target.classList.remove('frame-fade-in--entering');
        }, SETTLE_HOLD_MS);
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
// scroll runs at 'shown' for immediate feedback, and again on each 'turbo:frame-load' once real
// content has given the page its full height - until the user scrolls themselves or 8s pass.
var pendingTabScroll = null; // { nav: Element, deadline: epoch ms }

function scrollTabBarToTop(nav) {
    // The theme's header.topbar is position:fixed, so "top of the window" means just below it -
    // measured live rather than hard-coding its height, plus 8px breathing room
    var topbar = document.querySelector('header.topbar');
    var offset = (topbar ? topbar.offsetHeight : 0) + 8;
    var top = nav.getBoundingClientRect().top + window.scrollY - offset;
    window.scrollTo({ top: Math.max(top, 0), behavior: 'smooth' });
}

document.documentElement.addEventListener('shown.bs.tab', function (e) {
    if (e.target.closest('.modal, .offcanvas')) return;
    // A dropdown tab's screen sits in a .dropdown-menu inside the bar, so this finds the bar itself
    var nav = e.target.closest('.nav, [role="tablist"]');
    if (!nav) return;
    scrollTabBarToTop(nav);
    pendingTabScroll = { nav: nav, deadline: Date.now() + 8000 };
});

// A wheel/touch scroll from the user means they've taken over - stop re-aligning under them
['wheel', 'touchmove'].forEach(function (evt) {
    window.addEventListener(evt, function () { pendingTabScroll = null; }, { passive: true });
});

function realignPendingTabScroll() {
    if (!pendingTabScroll) return;
    if (Date.now() > pendingTabScroll.deadline || !document.contains(pendingTabScroll.nav)) {
        pendingTabScroll = null;
        return;
    }
    scrollTabBarToTop(pendingTabScroll.nav);
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

