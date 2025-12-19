import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "responses", "spinner", "micBtn", "hint", "welcome", "assistantType", "chatInterface"]

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
    const assistant_type = this.hasAssistantTypeTarget ? this.assistantTypeTarget.value : 'fund'
    if (!query) return

    // UI Updates
    this.hideWelcome()
    this.appendUserMessage(query)
    this.inputTarget.value = ""
    this.autoResize() // Reset height
    // this.setBusy("Thinking…")
    this.scrollToBottom()

    try {
      const html = await this.postForm("/assistants/ask", { query, assistant_type })
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
        const assistant_type = this.hasAssistantTypeTarget ? this.assistantTypeTarget.value : 'fund'
        formData.append("assistant_type", assistant_type)

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
    // We append the raw HTML content because the backend partial (assistants/_ask_frame)
    // already provides the necessary structure and styling, or targets a specific Turbo Frame.
    this.responsesTarget.insertAdjacentHTML("beforeend", htmlContent)
    this.removeDuplicateResponses()
  }

  // Prevents duplicate assistant responses by checking if a Turbo Frame with the same ID already exists
  removeDuplicateResponses() {
    const responses = this.responsesTarget.querySelectorAll('[id^="assistant_response_"]')
    const seenIds = new Set()

    responses.forEach(el => {
      if (seenIds.has(el.id)) {
        el.remove()
      } else {
        seenIds.add(el.id)
      }
    })
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
