import { Controller } from "@hotwired/stimulus"
import Reveal from "reveal.js"
import Markdown from "reveal.js/plugin/markdown/markdown.esm.js"
import Highlight from "reveal.js/plugin/highlight/highlight.esm.js"
import Notes from "reveal.js/plugin/notes/notes.esm.js"

export default class extends Controller {
  static targets = ["container", "slides", "source", "reveal"]

  connect() {
    this.deck = null
    this.boundHandleEsc = this.handleEsc.bind(this)
  }

  disconnect() {
    this.close()
  }

  async open() {
    console.log("[SlideshowController] Opening slideshow...")
    this.containerTarget.classList.remove("d-none")

    this.buildSlides()

    if (this.deck) {
      try {
        this.deck.destroy()
      } catch (e) {}
    }

    const isMobile = window.innerWidth <= 768

    this.deck = new Reveal(this.revealTarget, {
      plugins: [Markdown, Highlight, Notes],
      embedded: true,
      hash: false,
      respondToHashChanges: false,
      history: false,
      keyboard: true,
      touch: true,
      controls: true,
      controlsLayout: isMobile ? 'edges' : 'bottom-right',
      controlsBackArrows: 'visible',
      progress: true,
      center: false,
      transition: 'slide',
      width: '100%',
      height: '100%',
      margin: 0,
      minScale: 1,
      maxScale: 1,
      display: 'block'
    })

    // Add event listener to deck once created but before initialize if possible,
    // or right after. Reveal 4+ supports this.
    this.deck.on('ready', () => {
      console.log("[SlideshowController] Deck ready")
    })
    this.deck.on('slidechanged', event => {
      console.log("[SlideshowController] Slide changed", event.indexh)
      // DO NOT call this.deck.layout() here to avoid infinite recursion
    })

    try {
      await this.deck.initialize()
      this.deck.layout()

      // Debug: confirm slide count + initial position
      try {
        const total = this.revealTarget.querySelectorAll('.slides > section').length
        console.log('[SlideshowController] Reveal initialized. sections:', total, 'indices:', this.deck.getIndices())
      } catch (e) {}

      // Fullscreen
      if (this.containerTarget.requestFullscreen) {
        this.containerTarget.requestFullscreen()
      } else if (this.containerTarget.webkitRequestFullscreen) {
        this.containerTarget.webkitRequestFullscreen()
      }

      document.addEventListener('keydown', this.boundHandleEsc, true)

    } catch (err) {
      console.error("[SlideshowController] Failed to initialize Reveal.js", err)
    }
  }

  handleEsc(event) {
    if (event.key === "Escape") {
      this.close()
      event.preventDefault()
      event.stopPropagation()
    }
  }

  close() {
    this.containerTarget.classList.add("d-none")
    document.removeEventListener('keydown', this.boundHandleEsc, true)

    if (document.fullscreenElement || document.webkitFullscreenElement) {
       if (document.exitFullscreen) {
         document.exitFullscreen()
       } else if (document.webkitExitFullscreen) {
         document.webkitExitFullscreen()
       }
    }

    if (this.deck) {
      try {
        this.deck.destroy()
      } catch (e) {}
      this.deck = null
    }
  }

  next(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    console.log("[SlideshowController] next()", !!this.deck)
    if (this.deck) {
      try {
        const before = this.deck.getIndices()
        this.deck.next()
        console.log('[SlideshowController] next called')
      } catch (e) {
        console.warn('[SlideshowController] next failed', e)
      }
    }
  }

  prev(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    console.log("[SlideshowController] prev()", !!this.deck)
    if (this.deck) {
      try {
        const before = this.deck.getIndices()
        this.deck.prev()
        console.log('[SlideshowController] prev called')
      } catch (e) {
        console.warn('[SlideshowController] prev failed', e)
      }
    }
  }

  buildSlides() {
    this.slidesTarget.innerHTML = ""
    // Each message is rendered as a bootstrap card; some are user-only, some assistant-only.
    // Build slides from all cards so we get both Questions + Responses.
    const cards = Array.from(this.sourceTarget.querySelectorAll('.card'))

    console.log("[SlideshowController] Building slides from cards count:", cards.length)

    cards.forEach((card, idx) => {
      const isUserCard = !!card.querySelector('.ti-user')
      const isAssistantCard = !!card.querySelector('.ti-robot')
      console.log(`[SlideshowController] Card ${idx}: isUser=${isUserCard}, isAssistant=${isAssistantCard}`)

      // Question slide
      if (isUserCard) {
        const questionEl = card.querySelector('.fw-semibold')
        if (questionEl && questionEl.innerText.trim().length > 0) {
          const qSection = document.createElement('section')
          qSection.innerHTML = `
            <div class="step-badge">Question</div>
            <h2 class="question-text" style="font-size: 1.5em; margin-top: 40px;">${questionEl.innerText}</h2>
          `
          this.slidesTarget.appendChild(qSection)
          console.log("[SlideshowController] Added question slide")
        }
      }

      // Response slide
      const proseEl = card.querySelector('.prose')
      if (isAssistantCard && proseEl) {
        let currentSection = document.createElement('section')
        const badge = document.createElement('div')
        badge.className = "step-badge"
        badge.innerText = "Response"
        currentSection.appendChild(badge)

        const contentDiv = document.createElement('div')
        contentDiv.className = "presentation-content"
        const clonedProse = proseEl.cloneNode(true)

        clonedProse.querySelectorAll('table').forEach(table => {
           const wrapper = document.createElement('div')
           wrapper.className = "table-wrapper mb-4"
           table.classList.add('table', 'table-bordered', 'table-sm')
           table.parentNode.insertBefore(wrapper, table)
           wrapper.appendChild(table)
        })

        proseEl.querySelectorAll('canvas').forEach((canvas, idx) => {
           try {
              const imgData = canvas.toDataURL('image/png')
              const img = document.createElement('img')
              img.src = imgData
              img.className = "presentation-chart mb-4"
              img.style.maxHeight = "400px"
              img.style.width = "auto"
              img.style.display = "block"
              img.style.margin = "0 auto"

              const cloneCharts = clonedProse.querySelectorAll('[data-controller*="chart-renderer"], canvas')
              if (cloneCharts[idx]) {
                 const chartHeader = document.createElement('h4')
                 chartHeader.className = "text-primary text-center"
                 chartHeader.style.fontSize = "0.7em"
                 chartHeader.innerText = "Visual Analysis"
                 cloneCharts[idx].replaceWith(chartHeader, img)
              }
           } catch (e) {}
        })

        contentDiv.appendChild(clonedProse)
        currentSection.appendChild(contentDiv)

        if (currentSection.children.length > 1) {
           this.slidesTarget.appendChild(currentSection)
           console.log("[SlideshowController] Added response slide")
        }
      }
    })

    const finalCount = this.slidesTarget.querySelectorAll(':scope > section').length
    console.log("[SlideshowController] Final slide count:", finalCount)

    // If we somehow still have no sections, provide a fallback section so Reveal can navigate.
    if (finalCount === 0) {
      this.slidesTarget.innerHTML = '<section><h2>No slides generated</h2><p>There were no messages to present.</p></section>'
    }
  }
}
