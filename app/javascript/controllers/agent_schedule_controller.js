import { Controller } from "@hotwired/stimulus"

// Controls the Agent Schedule form interactions
export default class extends Controller {
  static targets = [
    "form",
    "enabledCheckbox",
    "scheduleFields",
    "frequencySelect",
    "weeklyDays",
    "monthlyDays",
    "dailyNote",
    "notifyTrigger",
    "notifyUsersContainer",
    "saveButton",
    "runNowButton",
    "runningStatus",
    "tagFilter",
    "recipientSelect"
  ]

  static values = {
    running: Boolean
  }

  connect() {
    this.toggleScheduleFields()
    this.updateRunOnOptions()
    this.toggleNotifyUsers()
  }

  // Enable/disable schedule fields based on enabled checkbox
  toggleScheduleFields() {
    if (!this.hasScheduleFieldsTarget || !this.hasEnabledCheckboxTarget) return

    const enabled = this.enabledCheckboxTarget.checked
    this.scheduleFieldsTarget.classList.toggle("opacity-50", !enabled)
    
    // Disable/enable all inputs within schedule fields
    const inputs = this.scheduleFieldsTarget.querySelectorAll("input, select, textarea")
    inputs.forEach(input => {
      if (!enabled) {
        input.setAttribute("disabled", "disabled")
      } else {
        input.removeAttribute("disabled")
      }
    })

    // Re-apply run on options logic after enabling
    if (enabled) {
      this.updateRunOnOptions()
    }
  }

  // Show/hide run_on_day options based on frequency
  updateRunOnOptions() {
    if (!this.hasFrequencySelectTarget) return

    const frequency = this.frequencySelectTarget.value

    // Hide all options first
    if (this.hasWeeklyDaysTarget) {
      this.weeklyDaysTarget.classList.add("d-none")
      const select = this.weeklyDaysTarget.querySelector("select")
      if (select) select.setAttribute("disabled", "disabled")
    }
    if (this.hasMonthlyDaysTarget) {
      this.monthlyDaysTarget.classList.add("d-none")
      const select = this.monthlyDaysTarget.querySelector("select")
      if (select) select.setAttribute("disabled", "disabled")
    }
    if (this.hasDailyNoteTarget) {
      this.dailyNoteTarget.classList.add("d-none")
    }

    // Show the appropriate option
    if (frequency === "daily") {
      if (this.hasDailyNoteTarget) {
        this.dailyNoteTarget.classList.remove("d-none")
      }
    } else if (frequency === "weekly") {
      if (this.hasWeeklyDaysTarget) {
        this.weeklyDaysTarget.classList.remove("d-none")
        const select = this.weeklyDaysTarget.querySelector("select")
        if (select) select.removeAttribute("disabled")
      }
    } else {
      // monthly, bimonthly, quarterly, half_yearly
      if (this.hasMonthlyDaysTarget) {
        this.monthlyDaysTarget.classList.remove("d-none")
        const select = this.monthlyDaysTarget.querySelector("select")
        if (select) select.removeAttribute("disabled")
      }
    }
  }

  // Show/hide notify users multi-select based on checkbox
  // Show/hide notify users multi-select based on notification checkboxes
toggleNotifyUsers() {
  if (!this.hasNotifyUsersContainerTarget) return

  // Check if ANY notification trigger checkbox is checked
  let anyChecked = false
  if (this.hasNotifyTriggerTarget) {
    this.notifyTriggerTargets.forEach(checkbox => {
      if (checkbox.checked) anyChecked = true
    })
  }

  // Show recipients container if any notification is enabled
  this.notifyUsersContainerTarget.classList.toggle("d-none", !anyChecked)
}

  // Filter users in the recipient select by tag
  filterUsersByTag() {
    if (!this.hasTagFilterTarget || !this.hasRecipientSelectTarget) return

    const selectedTag = this.tagFilterTarget.value.toLowerCase()
    const select = this.recipientSelectTarget
    const options = select.querySelectorAll("option")

    options.forEach(option => {
      if (!option.value) return // Skip placeholder

      const tags = (option.dataset.tags || "").toLowerCase()

      if (!selectedTag || tags.includes(selectedTag)) {
        option.style.display = ""
        option.disabled = false
      } else {
        option.style.display = "none"
        option.disabled = true
      }
    })

    // Refresh Select2 if present
    if (window.$ && $(select).data("select2")) {
      $(select).trigger("change.select2")
    }
  }
}
