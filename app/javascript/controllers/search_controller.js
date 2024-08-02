import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["searchInput", "perPageInput", "submit"]

    connect() {
        console.log("Search controller connected");
        this.debounceTimeout = null;
        this.previousSearchValue = this.searchInputTarget.value;
    }

    debouncedSearchInput(event) {
        console.log("debouncedSearchInput called");
        console.log(event.key);

        const isEnterKey = event.key === "Enter" || event.code === "Enter" || event.keyCode === 13;
        if (isEnterKey) {
            event.preventDefault();
            this.setSearchInput(event);
            return;
        }

        clearTimeout(this.debounceTimeout);
        this.debounceTimeout = setTimeout(() => {
            this.setSearchInput(event);
        }, 750);
    }

    setSearchInput(event) {
        const currentSearchValue = this.searchInputTarget.value;
        console.log(`setSearchInput called ${currentSearchValue}`);

        if (currentSearchValue === this.previousSearchValue && event.key !== "Enter") {
            console.log("Search value has not changed. Skipping submission.");
            return;
        }

        // let form = this.element;
        let form = $("#search_form");
        let actionUrl = window.location.href.split("?")[0];
        console.log(actionUrl);
        form.attr('action', actionUrl);
        // form.setAttribute('action', actionUrl);

        let query = window.location.search.substring(1);
        let vars = query.split('&');

        form.find("input[type='hidden']").remove(); // Remove old hidden inputs
        vars.forEach(keyVal => {
            console.log(`keyVal = ${keyVal}`);
            let keyValArr = keyVal.split('=');
            if (decodeURIComponent(keyValArr[0]) !== "search[value]" && decodeURIComponent(keyValArr[0]) !== "commit" && decodeURIComponent(keyValArr[0]) !== "page") {
                form.append(`<input type='hidden' name='${keyValArr[0]}' value='${keyValArr[1]}' />`);
            }
        });

        // Make the call
        let submit = form.find("input[type='submit']");
        submit.off('click').click();

        this.previousSearchValue = currentSearchValue;

        // Show spinner and disable input
        $("#search_spinner").show();
        $("#search_input").prop("disabled", true);
    }
}
