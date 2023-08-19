import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Sortable setup.")
    // Setup the sortable content
    new Sortable(deal_activities_tbody, {
        animation: 150,
        draggable: ".item",
        handle: ".handle",
        ghostClass: 'blue-background-class',
        onEnd: function(event) {
            console.log(event.item);
            let id = event.item.id.replace("deal_activity_", "");
            let url = `/deal_activities/${id}/update_sequence?sequence=${event.newIndex}`;

            // This nonsense is being done to trigger a turbo link call, to update the page inplace
            $("#deal_activity_sequence").val(event.newIndex);
            $("#deal_activity_id").val(id);
            $("#sort_link").attr("href", url);
            $("#sort_link")[0].click();
        }
    });  

    
  }
};
