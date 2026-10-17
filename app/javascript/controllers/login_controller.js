import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["password", "toggleIcon"]

    connect() {
        console.log("login controller connect");

        // Sometimes people leave the login window open, and invalidauthenticitytoken happens as server is restarted
        // Hence we reload the page every 5 mins
        setTimeout("location.reload();", 300000);
    }

    // Flip the password field between masked and clear text, and keep the eye icon
    // and its aria state in step with what the field is currently showing.
    togglePassword(event) {
        if (!this.hasPasswordTarget) return;

        const button = event.currentTarget;
        const show = this.passwordTarget.type === "password";

        // Reveal or re-mask the typed password
        this.passwordTarget.type = show ? "text" : "password";

        // Eye-off while visible (click to hide), eye while masked (click to show)
        if (this.hasToggleIconTarget) {
            this.toggleIconTarget.classList.toggle("ti-eye", !show);
            this.toggleIconTarget.classList.toggle("ti-eye-off", show);
        }
        button.setAttribute("aria-pressed", String(show));
        button.setAttribute("aria-label", show ? "Hide password" : "Show password");

        // Return focus to the field so the user can keep typing
        this.passwordTarget.focus();
    }
}
