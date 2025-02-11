# Kanban Board Functionality

## Boards Working

The Kanban board can function as a standalone feature or be associated with an underlying model (currently, deals).

---

## Kanban Board Working Independently

- Users can create a new board from the boards index page by providing a name.
- Example columns are automatically created using default ones stored in the entity settings.
- Users can add new columns using the "Add Column" button, requiring a name.
- Columns can be rearranged in any order using a JavaScript request to update their sequence.
- Users can add new cards using the "Add Item" button in each column.
  - Cards require a name and can also include notes, info, and tags.
- Cards can be moved between columns, updating the column ID of the card.
- Cards can be reordered within the same column, updating their sequence via a JavaScript request.
- Clicking a card opens an off-canvas panel displaying its complete details, allowing users to edit it.
- The edit card form contains the same fields as the create card form.

---

## Kanban Board Working with Deals

- **Deal** is the underlying model for the Kanban board (as the owner).
- **Deal Investor** is the underlying model for the Kanban card (as the data source).
- Kanban columns currently do not have an underlying model (ideally, it would be deal activities).

### Deal-Kanban Interactions

- A Kanban board is automatically created when a deal is created.
- The board view is the default view of the deal.
- Clicking the "Edit" button in the three-dot dropdown on the right side of the header allows users to edit the deal.
- Clicking "Add Item" triggers the form for the underlying model (in this case, the Deal Investor form).
- Creating a Deal Investor results in a new card in the selected column.
- Clicking a card opens an off-canvas panel displaying the full details of the Deal Investor, allowing edits.

---

## Movement of Columns and Cards

- The movement of columns and cards is managed by a JavaScript controller.
- When a card is dragged and dropped:
  - It checks for the closest card and is added after it.
  - The sequence of the subsequent cards is updated.
  - If dropped on an empty area, it is added at the end of the column.
- When a column is dragged and dropped:
  - It checks for the closest column and is added after it.

---

## Dynamic Updates of Cards and Columns

### Broadcasting Mechanism

- The **Kanban board, columns, and cards** each have their own Turbo broadcasts.
- When a card is **created or updated**, it broadcasts itself with the updated data.
- When the underlying model of a card (e.g., a Deal Investor) is updated:
  - The card data is rederived and triggers a Turbo broadcast.
- When a card’s **sequence or column is updated** (e.g., moving to a different column):
  - A simple card broadcast is insufficient.
  - The entire board is broadcasted to reflect the updated UI.
- A **board broadcast** only updates the board name, but the JavaScript controller automatically triggers a search request to fetch and refresh board data.
- When a **column’s name is updated**, it broadcasts itself.
- When a **column’s sequence is updated** or it is **deleted/undeleted (archived)**:
  - The entire board is broadcasted to reflect the changes.

---

This ensures real-time updates and seamless interaction within the Kanban board.
