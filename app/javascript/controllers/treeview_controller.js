import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { documentsFrameId: String }

    connect() {
        this.initTree();
        // Toggle the first level of children open on connect
        $(this.element).children("ul").children("li").children("ul").toggleClass("active")
    }

    initTree() {
        const el = this.element;
        const documentsFrameId = this.hasDocumentsFrameIdValue && this.documentsFrameIdValue
            ? this.documentsFrameIdValue
            : "documents_frame";

        $(el).find(".caret").bind("click", function(e) {
          e.preventDefault();
          // Ensure the children are shown and the class is toggled
          $(this).parent("li").children("ul").toggleClass("active");
          this.classList.toggle("caret-down");
        });

        $(el).find(".caret").children("a").bind('click', function(e) {
          e.preventDefault();
          let link = $(this).attr("href");
          if (link !== "#") {
            // Ensure the documents get loaded in the correct documents_frame for this widget
            const frame = document.getElementById(documentsFrameId);
            if (frame) {
              frame.src = link;
              frame.reload();
            }
          }
        });
      }


}
