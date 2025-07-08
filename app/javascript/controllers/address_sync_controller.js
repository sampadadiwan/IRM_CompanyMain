import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["address", "corrAddress"]

    connect() {
        this.corrChanged = false
        this.corrFocused = false
    }

    copyIfUnchanged() {
        const corrValue = this.corrAddressTarget.value.trim()

        // Only copy if user hasn’t changed it, OR it’s blank AND not focused (not being edited)
        if (!this.corrChanged || (corrValue === "" && !this.corrFocused)) {
            this.corrAddressTarget.value = this.addressTarget.value
        }
    }

    markAsChanged() {
        const corrValue = this.corrAddressTarget.value.trim()

        if (corrValue === "") {
            this.corrChanged = false
        } else {
            this.corrChanged = true
        }
    }

    focusIn() {
        this.corrFocused = true
    }

    focusOut() {
        this.corrFocused = false
        this.copyIfUnchanged() // Allow sync again if empty and unfocused
    }
}
