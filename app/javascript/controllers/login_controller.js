import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "passwordSection", "dividerSection", "magicSection",
        "passwordEmail", "magicEmail", "modeSwitch"
    ]

    connect() {
        console.log("login controller connect");

        // Sometimes people leave the login window open, and invalidauthenticitytoken happens as server is restarted
        // Hence we reload the page every 5 mins
        setTimeout("location.reload();", 300000);


        $("#togglePassword").on('click',function() {
            if ($("#user_password").attr('type') === 'password') {
                $("#user_password").attr('type', 'text');
            } else {
                $("#user_password").attr('type', 'password');
            }
          });

        // Keep focus in the password field when the eye is clicked, otherwise
        // the blur reads as "left the form" and folds the card back open.
        $("#togglePassword").off('mousedown.login').on('mousedown.login', function(e) {
            e.preventDefault();
        });

        // "both" means no method has been picked yet, so everything is on show.
        this.mode = "both";
    }

    // Focus landed in the password form.
    usePassword() {
        this.setMode("password");
    }

    // Focus landed in the magic-link form.
    useMagic() {
        this.setMode("magic");
    }

    // Focus left the login card altogether - put both methods back on show.
    handleFocusOut() {
        // focusout fires before the new element takes focus, so look on the next
        // tick. Checking activeElement rather than relatedTarget also means an
        // alt-tab away from the window leaves the card as it was.
        setTimeout(() => {
            if (this.element.contains(document.activeElement)) return;
            this.resetMode();
        }, 0);
    }

    // The "use the other method instead" button under the forms.
    toggleMode() {
        this.setMode(this.mode === "magic" ? "password" : "magic");
        // Drop the visitor straight into the field they just switched to.
        const field = this.mode === "magic" ? this.magicEmailTarget : this.passwordEmailTarget;
        field.focus();
    }

    setMode(mode) {
        // Nothing to switch between when the entity has password login turned off.
        if (!this.hasPasswordSectionTarget || mode === this.mode) return;

        this.mode = mode;
        const magic = mode === "magic";

        this.carryEmailAcross(magic);
        this.collapse(this.passwordSectionTarget, magic);
        // Once a method is chosen the "OR" has nothing left to divide.
        this.collapse(this.dividerSectionTarget, true);
        this.collapse(this.magicSectionTarget, !magic);

        this.modeSwitchTarget.classList.remove("d-none");
        this.modeSwitchTarget.textContent = magic
            ? this.modeSwitchTarget.dataset.magicLabel
            : this.modeSwitchTarget.dataset.passwordLabel;
    }

    resetMode() {
        if (!this.hasPasswordSectionTarget || this.mode === "both") return;

        this.mode = "both";
        this.collapse(this.passwordSectionTarget, false);
        this.collapse(this.dividerSectionTarget, false);
        this.collapse(this.magicSectionTarget, false);
        this.modeSwitchTarget.classList.add("d-none");
    }

    // Whatever address is already typed follows the visitor to the other form.
    carryEmailAcross(toMagic) {
        const from = toMagic ? this.passwordEmailTarget : this.magicEmailTarget;
        const to = toMagic ? this.magicEmailTarget : this.passwordEmailTarget;
        if (from.value && !to.value) to.value = from.value;
    }

    collapse(section, collapsed) {
        const wasCollapsed = section.classList.contains("is-collapsed");
        section.classList.toggle("is-collapsed", collapsed);
        // inert keeps a collapsed form out of the tab order and out of validation.
        section.toggleAttribute("inert", collapsed);
        // Only the sections actually coming back from collapsed replay the entrance.
        if (collapsed || !wasCollapsed) return;

        // Restart the staggered entrance for the section coming back into view.
        section.classList.remove("is-revealing");
        void section.offsetWidth;
        section.classList.add("is-revealing");
    }
}
