import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("Tree view controller");
        
        $('#jstree').jstree({
            "core" : {
              "themes" : {
                "variant" : "large"
              },
              expand_selected_onload: true,
            },
            expand_selected_onload: true,
            "checkbox" : {
              "keep_selected_style" : false
            },
            "plugins" : [ "wholerow", "checkbox" ]
          });
          
          $("#tree_view").jstree({ "plugins" : ["themes","html_data","ui"] }).on('ready.jstree', function (e, data) {
            console.log("jstree initialized");

            // Open the first level nodes
            $("#tree_view").jstree("open_node", $("#tree_view li"));
            let selected_folder_id = $("#selected_folder_id").val();
            
            // Open the selected folder
            $("#tree_view").jstree('open_node', `#folder_${selected_folder_id}`, function(e,d) {
              for (var i = 0; i < e.parents.length; i++) {
                $("#tree_view").jstree('open_node', e.parents[i]);
              };
            });

          });

          // Show documents in the clicked folder
          $("#tree_view li").on("click", "a", 
              function() {
                  document.location.href = this;
              }
          );
       
          
    }  
}
