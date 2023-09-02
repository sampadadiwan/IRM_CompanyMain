import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.initTree();
        $("#tree_view > ul > li > ul").toggleClass("active")
    }  

    initTree() {
      var toggler = $(".caret");
      var i;

        $(".caret").bind("click", function(e) {
          e.preventDefault();          
          // Ensure the children are shown and the class is toggled
          $(this).parent("li").children("ul").toggleClass("active");
          this.classList.toggle("caret-down");          
        });

        $(".caret").children("a").bind('click', function(e) {
          e.preventDefault();
          let link = $(this).attr("href");
          if (link !== "#") {
            // Ensure the documents get loaded in the documents_frame
            const frame = document.getElementById('documents_frame');
            frame.src=link;
            frame.reload();
          }
        });
      }

    
}
