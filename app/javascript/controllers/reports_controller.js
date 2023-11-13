import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("reports connect");
    }

    onChange(event) {
        console.log("reports on change");
        // const url = new URL(window.location.href);
        // url.searchParams.set("investor", event.target.value);
        window.location.href = event.target.value;
    }

}


