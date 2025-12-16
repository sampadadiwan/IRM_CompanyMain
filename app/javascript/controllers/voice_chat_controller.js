import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "responses", "spinner", "micBtn", "hint", "welcome"]

  connect() {
    this.mediaRecorder = null
    this.chunks = []
    this.stream = null
    this.isRecording = false
    this.originalInputHeight = null
    this.audioContext = null
    this.analyser = null
    this.silenceTimer = null
    this.speakingDetected = false
  }

  // Auto-resize the textarea as user types
  autoResize() {
    const el = this.inputTarget
    if (!this.originalInputHeight) this.originalInputHeight = el.offsetHeight

    el.style.height = 'auto'
    el.style.height = `${Math.min(el.scrollHeight, 150)}px` // Max height 150px
  }

  // Handle Enter key (Send) vs Shift+Enter (NewLine)
  handleEnter(e) {
    if (!e.shiftKey) {
      e.preventDefault()
      this.sendText()
    }
  }

  async sendText() {
    const query = (this.inputTarget.value || "").trim()
    if (!query) return

    // UI Updates
    this.hideWelcome()
    this.appendUserMessage(query)
    this.inputTarget.value = ""
    this.autoResize() // Reset height
    // this.setBusy("Thinking…")
    this.scrollToBottom()

    try {
      const html = await this.postForm("/assistants/ask", { query })
      this.appendAssistantResponse(html)
    } catch (err) {
      console.error(err)
      this.appendErrorMessage("Sorry, something went wrong. Please try again.")
    } finally {
      // this.setIdle()
      this.scrollToBottom()
    }
  }

  async startRecording(e) {
    if (e.type === 'touchstart') e.preventDefault() // Prevent ghost clicks on touch
    if (this.isRecording) return

    // this.setBusy("Listening…")
    this.isRecording = true
    this.chunks = []

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })

      // Silence detection setup
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
      this.analyser = this.audioContext.createAnalyser()
      this.analyser.fftSize = 256
      const source = this.audioContext.createMediaStreamSource(this.stream)
      source.connect(this.analyser)
      this.dataArray = new Uint8Array(this.analyser.frequencyBinCount)
      this.silenceStart = Date.now()
      this.speakingDetected = false
      this.detectSilence()

      this.mediaRecorder = new MediaRecorder(this.stream)

      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) this.chunks.push(event.data)
      }

      this.mediaRecorder.start()

      // UI Updates for Recording
      this.micBtnTarget.classList.add("mic-active")
      this.hintTarget.textContent = "Listening... (Stop speaking to send)"
      this.hintTarget.classList.add("text-danger", "fw-bold")
    } catch (err) {
      console.error(err)
      // this.setIdle()
      this.isRecording = false
      this.hintTarget.textContent = "Mic permission denied or unavailable."
    }
  }

  async stopRecording(e) {
    if (e && e.type === 'touchend') e.preventDefault()
    if (!this.isRecording || !this.mediaRecorder) return

    this.isRecording = false
    const recorder = this.mediaRecorder

    // UI Updates for Processing
    this.micBtnTarget.classList.remove("mic-active")
    // this.setBusy("Transcribing…")
    this.hintTarget.classList.remove("text-danger", "fw-bold")

    recorder.onstop = async () => {
      try {
        const blob = new Blob(this.chunks, { type: recorder.mimeType || "audio/webm" })

        // If recording was too short (clicked instead of held), treat as cancel or ignore
        if (blob.size < 1000) {
            this.cleanupStream()
            // this.setIdle()
            return
        }

        const file = new File([blob], "voice.webm", { type: blob.type })
        const formData = new FormData()
        formData.append("audio", file)

        this.hideWelcome()
        // Optionally append a placeholder like "🎤 Audio message..." if you want immediate feedback

        const html = await this.postMultipart("/assistants/transcribe", formData)
        this.appendAssistantResponse(html)
      } catch (err) {
        console.error(err)
        this.appendErrorMessage("Audio upload failed.")
      } finally {
        this.cleanupStream()
        // this.setIdle()
        this.scrollToBottom()
      }
    }

    recorder.stop()
  }

  cleanupStream() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
    if (this.audioContext) {
      this.audioContext.close()
      this.audioContext = null
    }
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame)
      this.animationFrame = null
    }
    this.mediaRecorder = null
    this.chunks = []
  }

  detectSilence() {
    if (!this.isRecording || !this.analyser) return

    this.analyser.getByteFrequencyData(this.dataArray)

    // Calculate volume
    let sum = 0
    for (let i = 0; i < this.dataArray.length; i++) {
      sum += this.dataArray[i]
    }
    let average = sum / this.dataArray.length

    const THRESHOLD = 10 // Adjust sensitivity as needed
    const SILENCE_DURATION = 1500 // 1.5 seconds of silence to trigger stop

    if (average > THRESHOLD) {
      this.silenceStart = Date.now()
      this.speakingDetected = true
    } else {
      // If we have detected speaking previously, and now it's silent enough...
      if (this.speakingDetected && (Date.now() - this.silenceStart > SILENCE_DURATION)) {
        this.stopRecording()
        return
      }
    }

    this.animationFrame = requestAnimationFrame(() => this.detectSilence())
  }


  hideWelcome() {
    if (this.hasWelcomeTarget) {
      this.welcomeTarget.classList.add("d-none")
    }
  }

  scrollToBottom() {
    const chatFeed = document.getElementById("chat-feed")
    if (chatFeed) {
        // slight delay to ensure DOM update
        setTimeout(() => {
            chatFeed.scrollTop = chatFeed.scrollHeight
        }, 50)
    }
  }

  appendUserMessage(text) {
    const html = `
      <div class="d-flex justify-content-end mb-3">
        <div class="bg-primary text-white rounded-4 py-2 px-3" style="border-bottom-right-radius: 4px !important;">
          ${this.escapeHtml(text)}
        </div>
      </div>
    `
    this.responsesTarget.insertAdjacentHTML("beforeend", html)
  }

  appendAssistantResponse(htmlContent) {
    // Wrap the response in a container if needed, or assume backend returns a nice partial.
    // Assuming backend returns just the content, let's wrap it in a bubble style on the client side
    // OR just append it if the backend partial already has the styling.
    // Based on the file context, it seems the backend returns HTML.
    // Let's assume the backend return needs to be wrapped or is a full partial.
    // To be safe with the new design, I'll wrap it in a left-aligned bubble container.

    const wrapper = `
      <div class="d-flex justify-content-start mb-3">
        <div class="bg-light text-dark rounded-4 py-3 px-3 shadow-sm" style="max-width: 85%; border-bottom-left-radius: 4px !important;">
          ${htmlContent}
        </div>
      </div>
    `
    // Note: If the backend returns a Turbo Stream or a full block, this might double wrap.
    // If the previous code was `this.responsesTarget.insertAdjacentHTML("afterbegin", html)`,
    // it implies the backend returns a stand-alone block.
    // However, a standard "chat" appends to the bottom ("beforeend").
    // I will use "beforeend" now instead of "afterbegin" to maintain chronological order.

    // For now, I will append the raw HTML. If it looks bad, I might need to adjust the backend partial too.
    // But since I can't see the backend partial, I will try to make the container generic.

    // Actually, looking at the previous code: `this.responsesTarget.insertAdjacentHTML("afterbegin", html)`
    // It was prepending. Chat usually appends. I changed the UI to be a feed, so appending makes more sense.

    // Let's trust the backend returns *something* renderable.
    // I'll wrap it to ensure it looks like a message from the bot.

    this.responsesTarget.insertAdjacentHTML("beforeend", wrapper)
  }

  appendErrorMessage(msg) {
     const html = `
      <div class="text-center text-danger small my-2">
        ${this.escapeHtml(msg)}
      </div>
    `
    this.responsesTarget.insertAdjacentHTML("beforeend", html)
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  async postForm(url, dataObj) {
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute("content")
    const body = new URLSearchParams(dataObj)

    const res = await fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/html" // Request HTML fragment
      },
      body
    })

    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return await res.text()
  }

  async postMultipart(url, formData) {
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute("content")

    const res = await fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Accept": "text/html"
      },
      body: formData
    })

    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return await res.text()
  }
}
