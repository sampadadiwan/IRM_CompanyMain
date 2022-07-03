import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("Tree view controller");
        
        $('#jstree').jstree({
            "core" : {
              "themes" : {
                "variant" : "large"
              }
            },
            "checkbox" : {
              "keep_selected_style" : false
            },
            "plugins" : [ "wholerow", "checkbox" ]
          });
          
          $("#tree_view").jstree({ "plugins" : ["themes","html_data","ui"] });
          $("#tree_view li").on("click", "a", 
              function() {
                  document.location.href = this;
              }
          );
      
          $("#tree_view").jstree("open_all")
          
       
          console.log("jstree initialized");
    }
}
