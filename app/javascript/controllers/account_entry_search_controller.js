import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("account entry search connect");

        let fund_id = $("#fund_id").val();
        let names = $("#name_list").val().split(";");

        $("#account_entry_name").autocomplete({
            source: names,
            minLength: 1,
            response: function (event, ui) {
                console.log(ui.content);
            },
            select: function (event, ui) {
                console.log(ui.item);
            }
        });

    }


}


