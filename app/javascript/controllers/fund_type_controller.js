import { Controller } from "@hotwired/stimulus"
import { whenControllerConnected } from "custom/controller_ready"

// New Fund: the type page (Closed-ended or Open-ended card, H5), then the form. Open-ended puts the evergreen step links back in the
// step bar after step 2 and swaps step 2's Save for Next; closed-ended parks those links outside the step
// bar (the wizard moves to the next linked step on submit, so they must not be there) and shows Save.
// Nothing is saved until Save / Create fund.
// Worked examples H1, H2, H5, E4 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples
export default class extends Controller {
  static targets = ["radio", "openOnly", "closedOnly", "evergreenStep", "parking", "bar", "continue"]
  // fixed: Edit of an open-ended fund — the type is fixed, so there are no radios.
  // chosen: the form came back after a failed create with the type already picked — skip the type page.
  static values = { fixed: String, chosen: Boolean }

  async connect() {
    // Controllers are lazy-loaded, so the wizard on this element may connect after us; its start-up
    // jumps to the first step, so wait for it before arranging the steps and opening step 1.
    await whenControllerConnected(this.application, this.element, "wizard")
    this.toggle()
    // H5: reopen at the fund details rather than the type page (the wizard starts on the first step)
    if (this.chosenValue) this.element.querySelector("#wizard_step_1")?.click()
  }

  // Step 1's "Change": back to the type page (H5)
  change(event) {
    event.preventDefault()
    this.element.querySelector("#wizard_step_0")?.click()
  }

  // Step 2 → the open-ended terms: an open-ended fund needs unit types (they become the classes), so
  // with none typed go back to step 1 and say so, rather than open an empty Classes step (X1)
  toEvergreen(event) {
    event.preventDefault()
    const unitTypes = this.element.querySelector("#fund_unit_types")
    const needed = this.element.querySelector("#unit_types_needed")
    if (unitTypes && unitTypes.value.split(",").every((u) => u.trim() === "")) {
      needed?.classList.remove("d-none")
      unitTypes.classList.add("is-invalid")
      this.element.querySelector("#wizard_step_1")?.click()
      unitTypes.focus()
      return
    }
    needed?.classList.add("d-none")
    unitTypes?.classList.remove("is-invalid")
    const next = this.element.querySelector("#wizard_step_3")
    if (next) { next.classList.remove("disabled"); next.click() }
  }

  toggle() {
    const open = this.fixedValue === "open_ended" || this.radioTargets.some((r) => r.checked && r.value === "open_ended")
    // H5: Continue on the type page only once a type is picked
    if (this.hasContinueTarget) this.continueTarget.disabled = !this.radioTargets.some((r) => r.checked)
    this.openOnlyTargets.forEach((el) => el.classList.toggle("d-none", !open))
    this.closedOnlyTargets.forEach((el) => el.classList.toggle("d-none", open))
    // The step bar lines up with the card under it: fund card (col-md-6) or evergreen card (col-md-8)
    // The step bar and the fund's own step cards widen with the evergreen card, so all line up
    this.barTargets.forEach((el) => {
      el.classList.toggle("col-md-8", open)
      el.classList.toggle("col-md-6", !open)
    })
    if (!this.hasParkingTarget) return
    // The open-ended steps follow the Features step (lp-folio-portfolio-dashboard)
    const stepTwo = this.element.querySelector('div.setup-panel a[href="#step-features"]')?.parentElement
    if (open && stepTwo) {
      // back into the step bar, in order, right after the Features step
      let after = stepTwo
      this.evergreenStepTargets.forEach((el) => { after.after(el); after = el })
    } else {
      this.evergreenStepTargets.forEach((el) => this.parkingTarget.appendChild(el))
    }
    // The wizard binds its step links when it starts; re-bind after moving them. The choice is made on
    // the type page, the wizard's first step, so restarting there is where the user already is.
    const wizard = this.application.getControllerForElementAndIdentifier(this.element, "wizard")
    if (wizard) wizard.initialize()
  }
}
