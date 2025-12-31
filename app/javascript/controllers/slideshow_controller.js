import { Controller } from "@hotwired/stimulus"
import Reveal from "reveal.js"
import Markdown from "reveal.js/plugin/markdown/markdown.esm.js"
import Highlight from "reveal.js/plugin/highlight/highlight.esm.js"
import Notes from "reveal.js/plugin/notes/notes.esm.js"

export default class extends Controller {
  static targets = ["container", "slides", "source", "reveal", "loading"]
  static values = { chatId: String }

  connect() {
    this.deck = null
    this.boundHandleEsc = this.handleEsc.bind(this)
  }

  disconnect() {
    this.close()
  }

  async openNew() {
    console.log("[SlideshowController] Opening AI-generated presentation...")
    const chatId = this.chatIdValue || this.element.dataset.slideshowChatIdValue
    if (!chatId) {
      console.error("[SlideshowController] No chat_id found")
      return
    }

    // Open the new AI-generated presentation in a new tab.
    // Generation happens asynchronously (job) and the page auto-updates via Turbo Streams.
    window.open(`/assistants/generate_slides?chat_id=${chatId}`, '_blank')
  }

  async openOld() {
    console.log("[SlideshowController] Opening direct transcript presentation...")

    // Switch to internal slideshow mode
    this.containerTarget.classList.remove("d-none")
    document.addEventListener('keydown', this.boundHandleEsc, true)

    // Request fullscreen on the container
    try {
      const elem = this.containerTarget
      if (elem.requestFullscreen) {
        await elem.requestFullscreen()
      } else if (elem.webkitRequestFullscreen) {
        await elem.webkitRequestFullscreen()
      }
    } catch (err) {
      console.warn("[SlideshowController] Fullscreen request failed", err)
    }

    this.showLoading()
    try {
      this.buildSlides()
      await this.initializeReveal()
    } finally {
      this.hideLoading()
    }
  }

  async open() {
    // Default to openNew for backward compatibility if needed,
    // but the UI now calls openNew or openOld specifically.
    this.openNew()
  }

  async fetchAndBuildSlides() {
    const chatId = this.chatIdValue || this.element.dataset.slideshowChatIdValue
    if (!chatId) throw new Error("No chat_id found")

    console.log(`[SlideshowController] Fetching slides for chat ${chatId}...`)
    const response = await fetch(`/assistants/generate_slides?chat_id=${chatId}`, {
      headers: { "Accept": "application/json" }
    })

    // When slides are not yet generated, the server returns 202 Accepted and the job
    // will update the presentation page via Turbo Streams.
    if (response.status === 202) return

    if (!response.ok) throw new Error(`Server returned ${response.status}`)

    const data = await response.json()
    if (data?.html) this.slidesTarget.innerHTML = data.html

    // Ensure chart-renderer controllers are initialized
    // Stimulus usually picks them up if they are added to the DOM,
    // but sometimes with Reveal.js's shadow DOM or internal cloning we might need a nudge.
    // Reveal.js 4+ works better with standard DOM.
  }

  async initializeReveal() {
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

    this.deck.on('ready', () => {
      console.log("[SlideshowController] Deck ready")
      // Trigger a layout update to ensure everything fits
      this.deck.layout()
    })

    try {
      await this.deck.initialize()
      this.deck.layout()

      const total = this.revealTarget.querySelectorAll('.slides > section').length
      console.log('[SlideshowController] Reveal initialized. sections:', total)
    } catch (err) {
      console.error("[SlideshowController] Failed to initialize Reveal.js", err)
    }
  }

  showLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("d-none")
      this.slidesTarget.classList.add("opacity-0")
    }
  }

  hideLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("d-none")
      this.slidesTarget.classList.remove("opacity-0")
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
    if (this.deck) this.deck.next()
  }

  prev(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    if (this.deck) this.deck.prev()
  }

  buildSlides() {
    this.slidesTarget.innerHTML = ""
    const cards = Array.from(this.sourceTarget.querySelectorAll('.message-wrapper, .card'))

    cards.forEach((card) => {
      const isUserCard = !!card.querySelector('.ti-user') || (card.classList.contains('message-wrapper') && !card.classList.contains('assistant-message-card'))
      const isAssistantCard = !!card.querySelector('.ti-robot') || card.classList.contains('assistant-message-card')

      if (isUserCard) {
        const questionEl = card.querySelector('.fw-semibold, .message-content')
        if (questionEl && questionEl.innerText.trim().length > 0) {
          const qSection = document.createElement('section')
          qSection.innerHTML = `
            <div class="step-badge">Question</div>
            <h2 class="question-text" style="font-size: 1.5em; margin-top: 40px;">${questionEl.innerText}</h2>
          `
          this.slidesTarget.appendChild(qSection)
        }
      }

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
        }
      }
    })

    if (this.slidesTarget.querySelectorAll(':scope > section').length === 0) {
      this.slidesTarget.innerHTML = '<section><h2>No slides generated</h2><p>There were no messages to present.</p></section>'
    }
  }
}
