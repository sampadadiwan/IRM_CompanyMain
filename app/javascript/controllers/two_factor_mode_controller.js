import { Controller } from "@hotwired/stimulus"

// Shows the authenticator-app onboarding block (download links + setup guide) only
// while the "Authenticator App" option is selected on the 2FA mode-selection screen.
//
// The block is genuinely irrelevant to someone choosing WhatsApp — there is no app to
// install in that mode — and it is the tallest thing on the page, so leaving it up
// buries the Continue button for half the users who see this screen.
//
// The markup ships with the block hidden (hidden attribute in the view) and this
// controller reveals it, so the initial state is correct before Stimulus connects.
export default class extends Controller {
  static targets = ["radio", "authenticatorHelp"]

  connect() {
    this.toggle()
  }

  // Bound to change on the radios; also called on connect so a re-rendered page
  // (for example after a validation error) reflects the restored selection.
  toggle() {
    const authenticatorSelected = this.radioTargets.some(
      (radio) => radio.checked && radio.value === "authenticator"
    )

    this.authenticatorHelpTargets.forEach((el) => {
      el.hidden = !authenticatorSelected
    })
  }
}
