import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("Tree view controller");
        this.initTree();

        // if($("#jstree_created").val() == 'false') {
        //   console.log("Creating jstree");
        //   this.initTree();
        // } else {
        //   console.log("Already created jstree");
        // }
    }  

    initTree() {
      // $("#jstree_created").val('true');

      $('#jstree').jstree({
        "core" : {
          "themes" : {
            "variant" : "large"
          },
          expand_selected_onload: true,
          "check_callback" : true,
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
        // $("#tree_view").jstree("open_all");
        
        let selected_folder_id = $("#selected_folder_id").val();
        
        // Open the selected folder
        $("#tree_view").jstree('open_node', `#folder_${selected_folder_id}`, function(e,d) {
          for (var i = 0; i < e.parents.length; i++) {
            $("#tree_view").jstree('open_node', e.parents[i]);
          };
        });

      });

      // // Show documents in the clicked folder
      $("#tree_view li").on("click", "a", 
          function() {
              // document.location.href = this;
              $("#tree_view").jstree('open_node', this);
              // This is done so we can load the documents_frame using turbo_frames
              let link = $(this).attr("href");
              if (link !== "#") {
                const frame = document.getElementById('documents_frame');
                frame.src=link;
                frame.reload();
              }
          }
      );
    }
}
