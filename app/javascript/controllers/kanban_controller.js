
import { Controller } from "@hotwired/stimulus";

export default class KanbanController extends Controller {
  connect() {
    this.cards = Array.from(document.getElementsByClassName("card img-task ui-sortable-handle"));
    this.columns = Array.from(document.getElementsByClassName("task-list-container"));
		this.tags = Array.from(document.getElementsByClassName("deal-investor-tag"));
		this.input = document.getElementById("kanban-search-input");
		this.input.value = sessionStorage['search_query'] || '';

		this.input.addEventListener("keydown", this.searchQuery.bind(this));
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

		Array.from(document.getElementsByClassName("offcanvas")).forEach(offcanvas => {
			offcanvas.addEventListener('hidden.bs.offcanvas', () => {
				this.columns.forEach(column => {
					column.style.zIndex = '100';
				});
			});
		})

		document.addEventListener("DOMContentLoaded", function() {
			const form = document.getElementById("kanban-search-form");
			this.input.addEventListener("keydown", function(event) {
				if (event.key === "Enter") {
					form.submit();
				}
			});
		});
  }


  click(event) {
		if (event.srcElement.classList.contains("deal-investor-tag")) {
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
      let load_data_id = '.offcanvas_load_data_link_' + event.srcElement.closest('.kanban-card').dataset.dealInvestorId
      $(load_data_id).find('span').trigger('click');
      $(load_data_id).hide();
		}
	}

	searchQuery(event) {
		sessionStorage.setItem('search_query', this.input.value);
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

	moveToNextColumn(event) {
    const draggedCard = event.target.closest(".kanban-card");
    const closestColumn = event.target.closest(".task-list-container");
		const targetColumn = this.columns[(this.columns.indexOf(closestColumn) + 1)];

    this.sendDropCardRequest(draggedCard.id, targetColumn.id, draggedCard.dataset.dealInvestorId, closestColumn, draggedCard);
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
		const initialColumn = draggedCard.closest('.task-list-container');
		let targetDealActivityId;
		let dealInvestorId;

		if (draggedCard && draggedCard instanceof Node) {
			let dropTarget = event.target;
			while (dropTarget) {
				if (dropTarget.classList.contains("connect-sorting")) {
					const columnContent = dropTarget.querySelector(".connect-sorting-content");
					columnContent.appendChild(draggedCard);
					targetDealActivityId = dropTarget.parentElement.dataset.dealActivityId;
					dealInvestorId = draggedCard.dataset.dealInvestorId;

					this.disableCardMovement();
					this.sendDropCardRequest(cardId, targetDealActivityId, dealInvestorId, initialColumn, draggedCard);
					break;
				}
				dropTarget = dropTarget.parentElement;
			}
		} else {
			console.error("Dragged card not found or invalid.");
		}
	}

	sendDropCardRequest(cardId, targetDealActivityId, dealInvestorId, initialColumn, draggedCard) {
    $.ajax({
      url: `/deal_activities/${cardId}/perform_activity_action.json`,
      type: "POST",
      data: {
        deal_activity: {
          completed: "true",
        },
        target_deal_activity_id: targetDealActivityId,
        deal_investor_id: dealInvestorId,
        initial_deal_activity_id: initialColumn.id
      },
      success: (response) => {
        console.log("Response of toggle completion:", response);
        draggedCard.id = response.current_deal_activity_id;
        const fadingLine = draggedCard.querySelector('.fading-line');
        fadingLine.style.background = `linear-gradient(to right, ${response.severity_color} 0%, transparent 100%)`;
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
        url: `/deal_activities/update_sequences.json`,
        type: "POST",
        data: {
            dragged_column_id: draggedColumn.id,
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
