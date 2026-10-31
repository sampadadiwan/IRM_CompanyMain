import { Controller } from "@hotwired/stimulus"

// Assistants page hold-to-speak (assistants/_composer): records while the mic is held, stops after a
// pause, and posts the audio to /assistants/transcribe, which answers with the same Turbo Stream as a
// typed question (assistants/ask.turbo_stream). Sending typed questions is the chat kit's composer.
export default class extends Controller {
  static targets = ["micBtn", "hint"]

  connect() {
    this.mediaRecorder = null
    this.chunks = []
    this.stream = null
    this.isRecording = false
    this.audioContext = null
    this.analyser = null
    this.silenceTimer = null
    this.speakingDetected = false
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
        // The open conversation, from the question box (it follows the conversation frame).
        formData.append("chat_id", this.chatId())

        // E17 — the server transcribes and answers with the same Turbo Stream as a typed question.
        await this.postTurboStream("/assistants/transcribe", formData)
      } catch (err) {
        console.error(err)
        if (this.hasHintTarget) this.hintTarget.textContent = "Audio upload failed. Please try again."
      } finally {
        this.cleanupStream()
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


  // The open conversation's id, from the question box's hidden field.
  chatId() {
    return this.element.querySelector("#assistant-composer input[name='chat_id']")?.value || ""
  }

  async postTurboStream(url, formData) {
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute("content")
    const res = await fetch(url, {
      method: "POST",
      headers: { "X-CSRF-Token": token, "Accept": "text/vnd.turbo-stream.html" },
      body: formData
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    window.Turbo.renderStreamMessage(await res.text())
  }
}
