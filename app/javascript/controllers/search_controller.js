import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["searchInput", "perPageInput", "submit"]

    connect() {
        this.debounceTimeout = null;
        this.previousSearchValue = this.searchInputTarget.value;
    }

    debouncedSearchInput(event) {

        const isEnterKey = event.key === "Enter" || event.code === "Enter" || event.keyCode === 13;
        if (isEnterKey) {
            event.preventDefault();
            this.setSearchInput(event);
            return;
        }

        clearTimeout(this.debounceTimeout);
        this.debounceTimeout = setTimeout(() => {
            this.setSearchInput(event);
        }, 900);
    }

    setSearchInput(event) {
        const currentSearchValue = this.searchInputTarget.value;
        console.log(`setSearchInput called ${currentSearchValue}`);

        if (currentSearchValue === this.previousSearchValue && event.key !== "Enter") {
            return;
        }

        const form = $(event.target).closest('form.search-form'); // Using class
        // Make the call
        let submit = form.find("input[type='submit']");
        submit.off('click').click();

        this.previousSearchValue = currentSearchValue;

        // Show spinner and disable input
        // only closest to the form
        form.find("#search_spinner").show();
        form.find("#search_input").prop("disabled", true);
    }
}
