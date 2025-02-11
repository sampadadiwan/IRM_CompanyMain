import { Controller } from "@hotwired/stimulus";

export default class KanbanBoardController extends Controller {
  connect() {
    this.setupOffcanvasCleanup();
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

    document.addEventListener("turbo:before-stream-render", this.handleStream.bind(this));

    document.getElementsByClassName("archived-columns")[0].addEventListener("click", this.achivedColumnsModal.bind(this));
	}

  /**
   * Sets up event listeners for all offcanvas elements to clear their content
   * when they are hidden. If a Turbo frame is found within the offcanvas, its
   * content is cleared. Otherwise, the content of the offcanvas body is cleared.
   */
  setupOffcanvasCleanup() {
    const offcanvasElements = document.querySelectorAll(".offcanvas");

    offcanvasElements.forEach(offcanvas => {
      offcanvas.addEventListener("hidden.bs.offcanvas", () => {
        const targetFrame = offcanvas.querySelector("turbo-frame");
        if (targetFrame) {
          targetFrame.innerHTML = ""; // Clear Turbo frame content
        } else {
          offcanvas.querySelector(".offcanvas-body").innerHTML = ""; // Clear offcanvas content
        }
      });
    });
  }

  /**
   * Handles the stream event and performs actions based on the event's target.
   *
   * The function performs the following actions based on the event's target:
   * - If the target is "user_alert", it hides all modal elements.
   * - If the target includes "board_", it closes any visible offcanvas elements.
   * - If the target includes "kanban_board_", it clicks the first search button and the button with class "btn btn-outline-primary show_details_link".
   */
  handleStream(event) {
    if (event.srcElement.target == "user_alert") {
      $(document).ready(function(){
        $('.modal').modal('hide');
      });
    } else if (event.srcElement.target.includes("board_")) {
      if (document.getElementsByClassName("offcanvas offcanvas-end show")[0] != undefined) {
        document.getElementsByClassName("offcanvas offcanvas-end show")[0].getElementsByClassName("offcanvas-close")[0].click();
      }
    }
    // if event.srcElement.target like kanban_board_19 or starts with kanban_board_
    // then hit the search button

    if (event.srcElement.target.includes("kanban_board_")) {
      $(".search-button").eq(0).click();
      $(".btn.btn-outline-primary.show_details_link").click();
    }
  }

  /**
   * Adds a new column to the Kanban board.
   *
   * This function triggers a modal to add a new Kanban column and adjusts the z-index of existing columns.
   * It also triggers a click event on a load data link to load data and hides the link afterwards.
   */
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

  /**
   * Toggles the archived columns modal and triggers the loading of archived kanban columns data.
   */
  achivedColumnsModal(event) {
    let modal_id = "modal_archived_columns_"+document.getElementsByClassName("scrumboard")[0].dataset.kanbanBoardId;
    const modal = new bootstrap.Modal(document.getElementById(modal_id));
    modal.toggle();
    let load_data_id = '.modal_archived_kanban_columns_load_data_link_' + document.getElementsByClassName("scrumboard")[0].dataset.kanbanBoardId;
    $(load_data_id).find('span').trigger('click');
    $(load_data_id).hide();
  }

  /**
   * Handles click events on the kanban board.
   *
   * returns {void|null} - Returns null if the card or target frame is not found.
   */
	click(event) {
		if (event.srcElement.classList.contains("card-tag")) {
			return;
		} else if (event.target.parentElement.classList.contains("move-to-next-column")) {
			this.moveToNextColumn(event);
    } else if (event.target.parentElement.classList.contains("move-to-up-column")) {
      this.moveToTopOfColumn(event);
		} else {
			// let offcanvas_id = event.target.closest('.kanban-card').dataset.offcanvasId;
			const offcanvas = new bootstrap.Offcanvas(document.getElementById("card_offcanvas_id"));

      let targetFrame = event.currentTarget.dataset.targetFrame;
      targetFrame = document.getElementById(targetFrame);
			let card = event.target.closest('.kanban-card')
      let url = card.dataset.offcanvasSrc;
      if (!card) {
        console.error("Card not found or invalid.");
        return null;
      }

      if (!targetFrame) {
        console.error("Target frame not found or invalid.");
        return null;
      }

      // Set the Turbo frame's src attribute to load the content
      targetFrame.setAttribute('src', url);

      // Show the offcanvas
			offcanvas.toggle();
			for(var i=0; i<this.columns.length; i++) {
				this.columns[i].style.zIndex = 'unset';
			}
		}
	}

  /**
   * Moves the dragged card to the next column in the Kanban board.
   */
  moveToNextColumn(event) {
    const draggedCard = event.target.closest(".kanban-card");
    const closestColumn = event.target.closest(".connect-sorting");
		const targetKanbanColumn = this.columns[1];
    this.sendDropCardRequest(draggedCard.id, targetKanbanColumn.id, draggedCard.dataset.kanbanCardId, closestColumn, draggedCard);
	}

  /**
   * Handles the edit event for a kanban board column.
   * Opens the edit column modal
   */
  edit(event) {
    let modal_id = "modal_kanban_column"+event.target.closest('.task-list-container').id;
    const modal = new bootstrap.Modal(document.getElementById(modal_id));
    modal.toggle();
    for(var i=0; i<this.columns.length; i++) {
      this.columns[i].style.zIndex = 'unset';
    }
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

  /**
   * Handles the drop event for a kanban card.
   *
   * This method is responsible for handling the drop event of a kanban card. It retrieves the card ID from the event,
   * finds the dragged card element, and determines the initial column it belongs to.
   * If the card is dropped in the same column, it reorders the cards within that column.
   * If the card is dropped in a different column, it appends the card to the new column, disables card movement, and sends a request to update the card's position on the server.
   *
   * Will log an error if the column ID is not found in the card's attributes or if the initial column
   * element is not found.
   */
	dropCard(event) {
		console.log("Dropping Card");
		const cardId = event.dataTransfer.getData("text/plain");
		let draggedCard = document.getElementById(cardId);
    const columnId = draggedCard.getAttribute('data-kanban-column-id');
    if (!columnId) {
        console.error(`Column ID not found in column div for card with ID ${cardId}`);
        return null;
    }

    // Find the column element using the extracted column ID
    const initialColumn = document.querySelector(`[data-kanban-column-id="${columnId}"]`);
    if (!initialColumn) {
        console.error(`Column with ID ${columnId} not found`);
        return null;
    }

		let targetKanbanColumnId;
		let kanbanCardId;

		if (draggedCard && draggedCard instanceof Node) {
			let dropTarget = event.target;
			while (dropTarget) {
				if (dropTarget.classList.contains("connect-sorting")) {
          if (dropTarget.dataset.kanbanColumnId == initialColumn.dataset.kanbanColumnId) {
            this.reorderCards(dropTarget, draggedCard, event);
            return;
          }
					const columnContent = dropTarget.querySelector(".connect-sorting-content");
					columnContent.appendChild(draggedCard);
					targetKanbanColumnId = dropTarget.dataset.kanbanColumnId;
          kanbanCardId = draggedCard.getAttribute('data-kanban-card-id');

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

  /**
   * Reorders the kanban cards within a column based on the dragged card's position.
   *
   * dropTarget - The target element where the card is dropped.
   * draggedCard - The card element that is being dragged.
   * Returns null if no .kanban-card elements are found inside the parent.
   */
  reorderCards(dropTarget, draggedCard, event) {
    let target = event.target.closest(".kanban-card");
    // event.target.closest("[id^='kanban_column_'], .connect-sorting.connect-sorting-todo");
    if (target) {
      console.warn("Closest .kanban-card element found");
    } else {
      console.warn("No Closest .kanban-card element found");
      const allCards = event.target.closest("[id^='kanban_column_'], .connect-sorting.connect-sorting-todo").querySelectorAll(".kanban-card");
      if (allCards.length > 0) {
        // Get the last card explicitly
        const lastCard = allCards[allCards.length - 1];
        console.log("Last card found:", lastCard);
        target = lastCard;
        // Perform actions with the last card
      } else {
        console.error("No .kanban-card elements found inside the parent.");
        return null;
      }
    }
    const parentElement = target.parentElement
    const cards = Array.from(event.currentTarget.getElementsByClassName("kanban-card"));
    const targetIndex = cards.indexOf(target);
    let sequence = parseInt(target.getAttribute("data-sequence"), 10);
    console.log("target Sequence:", sequence);
    console.log("target Index:", targetIndex);
    console.log("Dragged Card index:", cards.indexOf(draggedCard));
    const draggedCardIndex = cards.indexOf(draggedCard);
    if ((draggedCardIndex + 1) <= targetIndex) {
      parentElement.insertBefore(draggedCard, target.nextSibling);
    } else {
      parentElement.insertBefore(draggedCard, target);

      // Get the previous sibling of the target
      if (draggedCardIndex > 0) {
        // There is a card before draggedCard
        const previousCard = cards[draggedCardIndex - 1];
        sequence = parseInt(previousCard.getAttribute("data-sequence"), 10);
      } else {
        // No card exists before draggedCard
        sequence -= 1;
      }
    }
    console.log("Sequence:", sequence);
    const updatedCards = Array.from(event.currentTarget.getElementsByClassName("kanban-card"));
    this.disableCardMovement();
    this.sendReorderCardRequest(draggedCard.dataset.kanbanCardId, sequence);
  }


  moveToTopOfColumn(event) {
    const draggedCard = event.target.closest(".kanban-card");
    this.sendReorderCardRequest(draggedCard.dataset.kanbanCardId, 0);
  }

  sendReorderCardRequest(kanbanCardId, targetIndex) {
    $.ajax({
      url: `/kanban_cards/${kanbanCardId}/update_sequence.json`,
      type: "PATCH",
      data: {
        new_position: targetIndex
      },
      success: (response) => {
        console.log("Card sequence updated");
      },
      error: (xhr, status, error) => {
        console.error("Failed to update card status:", error);
      },
      complete: () => {
        this.enableCardMovement();
      }
    });
  }

  /**
   * Sends an AJAX request to move a kanban card to a new column.
   *
   * cardId - The ID of the card being moved.
   * targetKanbanColumnId - The ID of the target kanban column.
   * kanbanCardId - The ID of the kanban card.
   * initialColumn - The initial column element from which the card is being moved.
   * draggedCard - The card element being dragged.
   */
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

  /**
   * Handles the drop event for a kanban board column.
   *
   * event - The drop event triggered when a column is dropped.
   *
   * This function updates the position of the dragged column in the DOM and sends an AJAX request
   * to update the sequence of columns on the server. It also handles the visual feedback for the drag-and-drop action.
   *
   * The function performs the following steps:
   * 1. Retrieves the ID of the dragged column from the event's dataTransfer object.
   * 2. Gets the dragged column and the target column elements from the DOM.
   * 3. Checks if the dragged column is dropped on itself and returns if true.
   * 4. Determines the indices of the dragged and target columns in the columns array.
   * 5. Removes the dragged column from its parent element.
   * 6. Inserts the dragged column before the target column in the DOM.
   * 7. Updates the columns array to reflect the new order.
   * 8. Resets the position styles of the dragged column.
   * 9. Removes the "drag-enter" class from all columns.
   * 10. Disables card movement during the AJAX request.
   * 11. Sends an AJAX PATCH request to update the column sequence on the server.
   * 12. Logs the success or failure of the AJAX request.
   * 13. Re-enables card movement after the AJAX request completes.
   */
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
