import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["item", "noResults", "input", "clearButton"]

    filter(event) {
        const searchTerm = this.inputTarget.value.toLowerCase();
        let visibleCount = 0;
        
        this.itemTargets.forEach(item => {
            const text = item.textContent.toLowerCase();
            if (text.includes(searchTerm)) {
                item.style.display = "";
                visibleCount++;
            } else {
                item.style.display = "none";
            }
        });

        if (this.hasNoResultsTarget) {
            if (visibleCount === 0 && searchTerm.length > 0) {
                this.noResultsTarget.classList.remove("d-none");
            } else {
                this.noResultsTarget.classList.add("d-none");
            }
        }

        if (this.hasClearButtonTarget) {
            if (searchTerm.length > 0) {
                this.clearButtonTarget.classList.remove("d-none");
            } else {
                this.clearButtonTarget.classList.add("d-none");
            }
        }
    }

    clear() {
        this.inputTarget.value = "";
        this.filter();
    }
}
