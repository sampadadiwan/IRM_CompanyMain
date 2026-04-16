import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { documentsFrameId: String, selectedFolderId: String }

    connect() {
        this.initTree();
        this.setInitialOpenState();
        this.highlightCurrentFolder();
    }

    initTree() {
        const el = this.element;
        const documentsFrameId = this.hasDocumentsFrameIdValue && this.documentsFrameIdValue
            ? this.documentsFrameIdValue
            : "documents_frame";
        const controller = this;

        $(el).find(".caret").bind("click", function(e) {
          e.preventDefault();
          $(this).parent("li").children("ul").toggleClass("active");
          this.classList.toggle("caret-down");
        });

        $(el).find(".caret").children("a").bind('click', function(e) {
          e.preventDefault();
          const link = $(this).attr("href");
          controller.markSelectedFolder(this);
          if (link !== "#") {
            const frame = document.getElementById(documentsFrameId);
            if (frame) {
              frame.src = link;
              frame.reload();
            }
          }
        });
      }

    setInitialOpenState() {
        $(this.element).children("ul").children("li").children("ul").toggleClass("active")
    }

    highlightCurrentFolder() {
        if (!this.hasSelectedFolderIdValue) {
            return;
        }

        const selectedId = this.selectedFolderIdValue;
        const selectedLink = this.element.querySelector(`a[data-folder-id="${selectedId}"]`);

        if (selectedLink) {
            this.markSelectedFolder(selectedLink);
            this.expandAncestors(selectedLink);
        }
    }

    markSelectedFolder(link) {
        $(this.element).find("a.selected").removeClass("selected");
        $(link).addClass("selected");
        this.expandAncestors(link);
    }

    expandAncestors(link) {
        const nestedParents = $(link).parents("ul.nested");
        nestedParents.addClass("active");
        nestedParents.parent("li").children(".caret").addClass("caret-down");
    }
}
