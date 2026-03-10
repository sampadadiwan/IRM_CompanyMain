import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // No static targets needed if we find all frames dynamically

  connect() {
    // Check if there are any turbo-frames inside
    const frames = Array.from(this.element.querySelectorAll('turbo-frame'))
    if (frames.length > 0) {
      // AUTOMATIC HIDING:
      // We only hide on connect if:
      // 1. There is no content in any of the frames.
      // 2. There is at least one frame that is supposed to load (has a 'src').

      let hasAnyContent = frames.some(frame => {
        const content = frame.innerHTML.replace(/<!--[\s\S]*?-->/g, '').trim()
        return content.length > 0
      })

      let hasLoadingFrames = frames.some(frame => frame.hasAttribute('src'))

      if (!hasAnyContent && hasLoadingFrames) {
        this.element.classList.add("d-none")
      }

      // Initial check (in case content is already there or was just rendered)
      this.toggleVisibility()
    }
  }

  /**
   * Toggles the visibility of the widget based on whether the turbo-frame has content.
   * This is triggered by 'turbo:frame-load' bubbling up from any frame inside.
   */
  toggleVisibility(event) {
    const frames = Array.from(this.element.querySelectorAll('turbo-frame'))
    if (frames.length === 0) return

    // The 'turbo:frame-load' event fires AFTER the frame has finished loading.

    let hasAnyContent = false
    let allFinished = true

    frames.forEach(frame => {
      const content = frame.innerHTML.replace(/<!--[\s\S]*?-->/g, '').trim()
      const frameHasContent = content.length > 0

      if (frameHasContent) {
        hasAnyContent = true
      }

      // Turbo sets the 'busy' attribute while loading.
      if (frame.hasAttribute('src') && frame.hasAttribute('busy')) {
        allFinished = false
      }
    })

    if (hasAnyContent) {
      // Show the widget as soon as ANY frame has content
      this.element.classList.remove("d-none")
    } else if (allFinished) {
      // Only hide the widget if ALL frames have finished loading and none have content.
      // We only do this if there was at least one frame that was supposed to load.
      let hasLoadingFrames = frames.some(frame => frame.hasAttribute('src'))
      if (hasLoadingFrames) {
        const widgetId = this.element.dataset.widgetId
        this.element.classList.add("d-none")
        console.warn(`Turbo Frame Visibility Controller: No content found in any frames after loading. Hiding widget ID: ${widgetId}. Frames checked:`, frames)
      }
    }
  }
}
