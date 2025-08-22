// controllers/formula_generator_controller.js
import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
    static targets = ["name", "ruleType", "entryType", "description", "generateButton"]
    static values = { url: String }

    connect() {
        console.log("FormulaGeneratorController connected!")
    }

    async generate() {
        const name = this.nameTarget.value
        const ruleType = this.ruleTypeTarget.value
        const entryType = this.entryTypeTarget.value
        const description = this.descriptionTarget.value

        if (!name && !ruleType && !description) {
            console.log("No params provided. Skipping request.")
            return
        }
        // Disable button + show spinner
        this.setLoadingState(true)

        let params = new URLSearchParams()
        params.append("name", name)
        params.append("rule_type", ruleType)
        params.append("entry_type", entryType)
        params.append("description", description)
        params.append("target", "formula_form")

        try {
            await get(`${this.urlValue}?${params.toString()}`, {
                responseKind: "turbo-stream"
            })
        } finally {
            // Always re-enable button + hide spinner
            this.setLoadingState(false)
        }
    }

    setLoadingState(isLoading) {
        const button = this.generateButtonTarget
        const spinner = button.querySelector(".spinner-border")
        const text = button.querySelector(".button-text")

        if (isLoading) {
            button.disabled = true
            spinner.classList.remove("d-none")
            text.textContent = "Generating..."
        } else {
            button.disabled = false
            spinner.classList.add("d-none")
            text.textContent = "Generate Formula"
        }
    }
}
