import { Controller } from "@hotwired/stimulus";

export default class BoardController extends Controller {
  connect() {
		this.cards = Array.from(document.getElementsByClassName("kanban-card"));
    this.columns = Array.from(document.getElementsByClassName("task-list-container"));
    this.editButtons = Array.from(document.getElementsByClassName("column-edit"));
    this.addColumnButtons = Array.from(document.getElementsByClassName("column-add"));
    this.archiveButtons = Array.from(document.getElementsByClassName("column-archive"));
    this.tags = Array.from(document.getElementsByClassName("card-tag"));

		this.cards.forEach(card => {
      card.addEventListener("dragstart", this.dragStart.bind(this));
      card.addEventListener("click", this.click.bind(this));
    });

		this.columns.forEach(column => {
			column.addEventListener("dragstart", this.dragColumnStart.bind(this));
      column.addEventListener("dragover", this.dragOver.bind(this));
      column.addEventListener("dragenter", this.dragEnter.bind(this));
      column.addEventListener("dragleave", this.dragLeave.bind(this));
      column.addEventListener("drop", this.drop.bind(this));
		});

    this.editButtons.forEach(editButton => {
      editButton.addEventListener("click", this.edit.bind(this));
    })

    this.addColumnButtons.forEach(addColumnButton => {
      addColumnButton.addEventListener("click", this.addColumn.bind(this));
    })

    this.archiveButtons.forEach(archiveButton => {
      archiveButton.addEventListener("click", this.archive.bind(this));
    })

    document.addEventListener("turbo:before-stream-render", this.closeModal.bind(this));

    document.getElementsByClassName("archived-columns")[0].addEventListener("click", this.achivedColumnsModal.bind(this));
	}

  closeModal(event) {
    if (event.srcElement.target == "user_alert") {
      $(document).ready(function(){
        $('.modal').modal('hide');
      });
    } else if (event.srcElement.target.includes("board_")) {
      if (document.getElementsByClassName("offcanvas offcanvas-end show")[0] != undefined) {
        document.getElementsByClassName("offcanvas offcanvas-end show")[0].getElementsByClassName("offcanvas-close")[0].click();
      }
    }
  }

  addColumn(event) {
    let modal_id = "modal_add_kanban_column"+event.target.closest('.task-list-section').id;
    const modal = new bootstrap.Modal(document.getElementById(modal_id));
    modal.toggle();
    for(var i=0; i<this.columns.length; i++) {
      this.columns[i].style.zIndex = 'unset';
    }
    let load_data_id = '.modal_add_kanban_column_load_data_link_' + event.srcElement.closest('.task-list-section').id;
    $(load_data_id).find('span').trigger('click');
    $(load_data_id).hide();
  }

  achivedColumnsModal(event) {
    console.log("A");
    let modal_id = "modal_archived_columns_"+document.getElementsByClassName("scrumboard")[0].dataset.kanbanBoardId;
    const modal = new bootstrap.Modal(document.getElementById(modal_id));
    modal.toggle();
    let load_data_id = '.modal_archived_kanban_columns_load_data_link_' + document.getElementsByClassName("scrumboard")[0].dataset.kanbanBoardId;
    $(load_data_id).find('span').trigger('click');
    $(load_data_id).hide();
  }

	click(event) {
		if (event.srcElement.classList.contains("card-tag")) {
			return;
		} else if (event.target.parentElement.classList.contains("move-to-next-column")) {
			this.moveToNextColumn(event);
		} else {
			let offcanvas_id = event.target.closest('.kanban-card').dataset.offcanvasId;
			const offcanvas = new bootstrap.Offcanvas(document.getElementById(offcanvas_id));
			offcanvas.toggle();
			for(var i=0; i<this.columns.length; i++) {
				this.columns[i].style.zIndex = 'unset';
			}
      let load_data_id = '.offcanvas_load_data_link_' + event.srcElement.closest('.kanban-card').id;
      $(load_data_id).find('span').trigger('click');
      $(load_data_id).hide();
		}
	}

  moveToNextColumn(event) {
    const draggedCard = event.target.closest(".kanban-card");
    const closestColumn = event.target.closest(".connect-sorting");
		const targetKanbanColumn = this.columns[1];
    this.sendDropCardRequest(draggedCard.id, targetKanbanColumn.id, draggedCard.dataset.kanbanCardId, closestColumn, draggedCard);
	}

  edit(event) {
    console.log("s");

    let modal_id = "modal_kanban_column"+event.target.closest('.task-list-container').id;
    const modal = new bootstrap.Modal(document.getElementById(modal_id));
    modal.toggle();
    for(var i=0; i<this.columns.length; i++) {
      this.columns[i].style.zIndex = 'unset';
    }
    let load_data_id = '.modal_kanban_column_load_data_link_' + event.srcElement.closest('.task-list-container').id;
    $(load_data_id).find('span').trigger('click');
    $(load_data_id).hide();
  }

  archive(event) {
    $.ajax({
      url: `/kanban_columns/${event.srcElement.closest(".task-list-container").id}/delete_column.json`,
      type: 'DELETE',
      dataType: 'json',
      success: function(response) {
        console.log('Update successful!');
      },
      error: function(xhr) {
        console.log('Update failed: ' + xhr.responseText);
      }
    });
  }

	dragStart(event) {
    event.dataTransfer.setData("text/plain", event.currentTarget.id);
  }

	dragColumnStart(event) {
		if (!event.srcElement || !event.srcElement.classList.contains("task-list-container")) {
			return;
		}
		event.dataTransfer.setData("text/plain", event.currentTarget.id);
	}

  dragOver(event) {
    event.preventDefault();
  }

  dragEnter(event) {
    event.target.classList.add("drag-enter");
  }

  dragLeave(event) {
    event.target.classList.remove("drag-enter");
  }

	drop(event) {
		console.log("Dropping");
		event.preventDefault();
		let draggedElement = document.getElementById(event.dataTransfer.getData("text/plain"));
		if (draggedElement.classList.contains("task-list-container")) {
			this.dropColumn(event);
		} else {
			this.dropCard(event);
		}
	}

	dropCard(event) {
		console.log("Dropping Card");
		const cardId = event.dataTransfer.getData("text/plain");
		let draggedCard = document.getElementById(cardId);
		const initialColumn = draggedCard.closest('.connect-sorting');
		let targetKanbanColumnId;
		let kanbanCardId;

		if (draggedCard && draggedCard instanceof Node) {
			let dropTarget = event.target;
			while (dropTarget) {
				if (dropTarget.classList.contains("connect-sorting")) {
					const columnContent = dropTarget.querySelector(".connect-sorting-content");
					columnContent.appendChild(draggedCard);
					targetKanbanColumnId = dropTarget.dataset.kanbanColumnId;
					kanbanCardId = draggedCard.dataset.kanbanCardId;

					this.disableCardMovement();
					this.sendDropCardRequest(cardId, targetKanbanColumnId, kanbanCardId, initialColumn, draggedCard);
					break;
				}
				dropTarget = dropTarget.parentElement;
			}
		} else {
			console.error("Dragged card not found or invalid.");
		}
	}

	sendDropCardRequest(cardId, targetKanbanColumnId, kanbanCardId, initialColumn, draggedCard) {
    $.ajax({
      url: `/kanban_cards/${kanbanCardId}/move_kanban_card.json`,
      type: "PATCH",
      data: {
        deal_activity: {
          completed: "true",
        },
        target_kanban_column_id: targetKanbanColumnId,
        kanban_card_id: kanbanCardId,
        initial_kanban_column_id: initialColumn.dataset.kanbanColumnId
      },
      success: (response) => {
        console.log("Response of toggle completion:", response);
        draggedCard.id = response.current_deal_activity_id;
        let movedCard = document.getElementById(response.current_deal_activity_id);
        movedCard.addEventListener("dragstart", this.dragStart.bind(this));
        movedCard.addEventListener("click", this.click.bind(this));
      },
      error: (xhr, status, error) => {
        console.error("Failed to update card status:", error);
        if (initialColumn.querySelector(".connect-sorting-content").children.length > 0) {
          initialColumn.querySelector(".connect-sorting-content").insertBefore(draggedCard, initialColumn.querySelector(".connect-sorting-content").firstChild);
        } else {
          initialColumn.querySelector(".connect-sorting-content").appendChild(draggedCard);
        }
      },
      complete: () => {
        this.enableCardMovement();
      }
    });
  }

	dropColumn(event) {
    const draggedColumnId = event.dataTransfer.getData("text/plain");
    const draggedColumn = document.getElementById(draggedColumnId);
    const targetColumn = event.currentTarget;

    if (draggedColumn === targetColumn) {
        return;
    }

    const targetIndex = this.columns.indexOf(targetColumn);
    const draggedIndex = this.columns.indexOf(draggedColumn);

    const parentElement = draggedColumn.parentElement;
    parentElement.removeChild(draggedColumn);

    targetColumn.parentElement.insertBefore(draggedColumn, this.columns[targetIndex]);

    this.columns.splice(draggedIndex, 1);
    this.columns.splice(targetIndex, 0, draggedColumn);

    draggedColumn.style.left = "";
    draggedColumn.style.top = "";

    this.columns.forEach(column => {
        column.classList.remove("drag-enter");
    });

    let newPosition = this.columns.indexOf(draggedColumn) + 1;
    this.disableCardMovement();
    $.ajax({
        url: `/kanban_columns/${draggedColumn.id}/update_sequence.json`,
        type: "PATCH",
        data: {
            new_position: newPosition
        },
        success: function(response) {
            console.log("Updated sequence of columns sent to the server successfully.");
        },
        error: function(xhr, status, error) {
            console.error("Failed to send updated sequence of columns to the server:", error);
        },
        complete: () => {
            this.enableCardMovement();
        }
    });
	}

	disableCardMovement() {
    this.cards.forEach(card => {
      card.draggable = false;
    });
    this.element.classList.add('kanban-disabled');
  }

  enableCardMovement() {
    this.cards.forEach(card => {
      card.draggable = true;
    });
    this.element.classList.remove('kanban-disabled');
  }
}
