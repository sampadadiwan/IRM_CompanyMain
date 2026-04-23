import { Controller } from "@hotwired/stimulus";

export default class DraggableRowController extends Controller {
  static targets = ["column"];

  connect() {
    this.columns = this.columnTargets;
    this.columns.forEach(column => {
      column.setAttribute('draggable', true);
      column.addEventListener("dragstart", this.dragStart.bind(this));
      column.addEventListener('dragover', this.dragOver.bind(this));
      column.addEventListener("drop", this.drop.bind(this));
      column.addEventListener("dragend", this.dragEnd.bind(this));
    });
  }

  dragStart(event) {
    event.target.classList.add('dragging');
    this.draggedIndex = event.target.dataset.index;  // Store the index of the dragged element
    this.draggedKey = event.target.dataset.key;      // Store the key of the dragged element
  }

  dragOver(event) {
    event.preventDefault();
    const draggingElement = document.querySelector('.dragging');
    const afterElement = this.getDragAfterElement(event.clientY);

    if (afterElement == null) {
      this.element.querySelector('tbody').appendChild(draggingElement);
    } else {
      this.element.querySelector('tbody').insertBefore(draggingElement, afterElement);
    }
  }

  drop(event) {
    event.preventDefault();
    const draggingElement = document.querySelector('.dragging');
    draggingElement.classList.remove('dragging');
    
    this.sendColumnInfo(draggingElement);
  }

  sendColumnInfo(draggingElement) {
    const rowId = draggingElement.dataset.rowId;
    const rows = Array.from(this.element.querySelectorAll('tbody tr.column'));
    const newIndex = rows.indexOf(draggingElement);

    if (newIndex === -1) return;

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

    fetch(`/grid_view_preferences/${rowId}/update_column_sequence.json`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      body: JSON.stringify({ index: newIndex })
    })
    .then(response => {
      if (response.ok) {
        console.log('Sequence updated successfully');
        // Trigger preview refresh if the report-builder controller is present
        const rbController = this.element.closest('[data-controller~="report-builder"]');
        if (rbController) {
          const stimulusController = this.application.getControllerForElementAndIdentifier(rbController, 'report-builder');
          if (stimulusController) stimulusController.loadPreview();
        }
      } else {
        console.error('Failed to update sequence');
      }
    })
    .catch(error => console.error('Error updating sequence:', error));
  }

  dragEnd(event) {
    event.target.classList.remove('dragging');
  }

  getDragAfterElement(y) {
    const draggableElements = [...this.columns].filter(element => !element.classList.contains('dragging'));

    return draggableElements.reduce((closest, child) => {
      const box = child.getBoundingClientRect();
      const offset = y - box.top - box.height / 2;

      if (offset < 0 && offset > closest.offset) {
        return { offset: offset, element: child };
      } else {
        return closest;
      }
    }, { offset: Number.NEGATIVE_INFINITY }).element;
  }
}
