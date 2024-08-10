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
    const targetClass = `column_${draggingElement.dataset.key}`
    const updatedColumns = Array.from(document.getElementsByClassName('column'))
    const draggedIndex = updatedColumns.findIndex(column => 
      column.classList.contains(targetClass)
    );

    const columnInfo = {
      index: draggedIndex,
      key: draggingElement.dataset.key
    };

    $.ajax({
      url: `/grid_view_preferences/${draggingElement.dataset.rowId}/update_column_sequence.json`,
      type: 'PATCH',
      dataType: 'json',
      data: columnInfo,
      success: function(response) {
        console.log('Update successful!');
      },
      error: function(xhr) {
        console.log('Update failed: ' + xhr.responseText);
      }
    });
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
