import { initSelect2 } from "custom/select2_handler"

/**
 * FIX FOR TURBO LAZY-LOADED FRAMES WITH PAGINATION
 * Fix for Turbo Rails bug where event delegation breaks in lazy-loaded frames
 * after page restoration from cache (browser back/forward).
 *
 * The issue: When Turbo restores a page from cache, turbo-frames with loading="lazy"
 * that were previously loaded don't re-trigger turbo:frame-load, so Turbo's internal
 * event delegation for data-turbo-frame links breaks.
 *
 * Solution: Intercept pagination clicks inside any turbo-frame that has loading="lazy"
 * attribute. Frames that don't have this attribute work fine with normal Turbo handling.
 */
const loadingFrames = new Set();

// Global click handler to fix pagination in lazy-loaded frames
// Uses capture phase (true) to intercept before Turbo's handler
document.addEventListener('click', (event) => {
  // Fast path: ignore non-link clicks
  const link = event.target.closest('a[data-turbo-frame]');
  if (!link) return;

  const targetFrameId = link.getAttribute('data-turbo-frame');
  // Skip _top targets - those navigate the full page
  if (targetFrameId === '_top') return;

  const insideFrame = link.closest('turbo-frame');
  // Only intervene for links inside lazy-loaded frames (has loading attribute)
  if (!insideFrame || !insideFrame.hasAttribute('loading')) return;

  const targetFrame = document.getElementById(targetFrameId);
  if (!targetFrame) return;

  // Prevent race conditions from rapid clicks
  if (loadingFrames.has(targetFrameId)) {
    event.preventDefault();
    return;
  }

  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();

  loadingFrames.add(targetFrameId);

  fetch(link.href, {
    headers: {
      'Turbo-Frame': targetFrameId,
      'Accept': 'text/html'
    }
  })
  .then(response => {
    if (!response.ok) {
      throw new Error(`Failed to load turbo frame (${response.status})`);
    }
    return response.text();
  })
  .then(html => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, 'text/html');
    const escapedFrameId = CSS.escape(targetFrameId);
    const newFrameContent = doc.querySelector(`turbo-frame#${escapedFrameId}`);

    if (newFrameContent) {
      targetFrame.innerHTML = newFrameContent.innerHTML;
      // Re-initialize Select2 for the new content
      initSelect2(targetFrame);
      targetFrame.dispatchEvent(new Event('turbo:frame-load', { bubbles: true }));
    }
  })
  .catch(error => {
    console.error('Error loading turbo frame:', error);
  })
  .finally(() => {
    loadingFrames.delete(targetFrameId);
  });
}, true);
