import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
  }

  newDealMsg(event) {
    console.log("newDealMsg");
    let ids = [];
    let checked = $('.deal_investor_id_cb:checkbox:checked');
    for (var i = 0; i < checked.length; i++) { 
        ids.push(checked[i].value); 
    }

    $("#new_nudge").attr("href", function(i, href) {
        let idq = ids.join(",");
        let newhref = href + `?deal_investor_ids=${idq}`;
        console.log(newhref);
        return newhref;
    });

    $(`#new_nudge`).find('span').trigger('click'); 

  }
};
