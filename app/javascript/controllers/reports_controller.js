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


    filter(event) {
        console.log("reports on filter");
        // const url = new URL(window.location.href);
        // url.searchParams.set("investor", event.target.value);
        window.location.href = `/reports?card=true&category=${event.target.value}`;
    }

    search(event) {
        let search_term = event.target.value;
        console.log(`reports on search ${search_term}`);
        $(".single-note-item").each(function() {
            console.log($(this).text());
            if ($(this).text().search(new RegExp(search_term, "i")) < 0) {
                $(this).hide();
            } else {
                $(this).show();
            }
        });
    }

}


