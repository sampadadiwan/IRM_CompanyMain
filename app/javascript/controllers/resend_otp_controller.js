// app/javascript/controllers/resend_otp_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["button", "timer", "form"]
    static values = { waitTime: Number }

    connect() {
        this.startCooldown()
    }

    handleSubmit(event) {
        event.preventDefault() // Prevent default submission

        this.startCooldown()  // Restart 90-second cooldown
        this.formTarget.submit() // Submit the form manually
    }

    startCooldown() {
        let remaining = this.waitTimeValue || 90

        this.disableButton(remaining)

        const interval = setInterval(() => {
            remaining--
            if (remaining <= 0) {
                clearInterval(interval)
                this.enableButton()
            } else {
                this.updateTimer(remaining)
            }
        }, 1000)
    }

    disableButton(seconds) {
        this.buttonTarget.disabled = true
        this.updateTimer(seconds)
    }

    updateTimer(remaining) {
        this.timerTarget.textContent = `Resend available in ${remaining}s`
    }

    enableButton() {
        this.buttonTarget.disabled = false
        this.timerTarget.textContent = ""
    }
}
