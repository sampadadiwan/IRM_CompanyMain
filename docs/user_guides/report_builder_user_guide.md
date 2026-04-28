# Report Builder User Guide

The **Report Builder** is a powerful self-service tool that allows you to create custom data exports across multiple tables in the IRM system. You can join related data, perform aggregations (like summing commitment amounts), apply complex filters, and even create pivot tables—all without writing any code.

---

## 1. Getting Started

### Creating a New Report
1. Navigate to the **Reports** list page.
2. Click the **"New Report (Builder)"** button.
3. **Choose a Starting Table:** Select the primary table for your report (e.g., *Investor*, *Fund*, or *Capital Commitment*). This is the "Root" of your report.
4. Once selected, you will be taken to the **Builder Interface**.

### Naming Your Report
Click on the report name (default: "Untitled Report") at the top left to rename it. Your changes are saved automatically as you type.

---

## 2. The Builder Interface

The builder is organized into three main panels:

1.  **Available Columns (Left):** A searchable palette of all fields available from your starting table and any joined tables.
2.  **Selected Columns (Center):** The structure of your report. Here you can reorder columns, set custom labels, and configure aggregations.
3.  **Configuration (Right):** Manage table relations (joins), apply filters, and set default sorting.

---

## 3. Building Your Report

### Adding Columns
*   **From the Palette:** Click the **(+)** icon next to any field in the left panel to add it to your report.
*   **Search:** Use the search bar at the top of the palette to find specific fields quickly.
*   **Reordering:** In the center panel, click and drag the **grip handle** (⋮⋮) to change the column order.
*   **Removing:** Click the **Trash** icon next to a selected column to remove it.

### Joining Related Tables
To include data from other tables (e.g., adding *Capital Commitments* to an *Investor* report):
1.  Go to the **Relations & Joins** section in the right panel.
2.  Select a relation from the **"+ Add new relation..."** dropdown.
3.  Click **Add**.
4.  New fields for that table will now appear in the **Available Columns** palette on the left.

### Aggregating Data
When you add columns from a "one-to-many" relation (like an Investor having multiple Commitments), you must choose how to summarize that data:
*   **Sum:** Total value (e.g., Total Committed Amount).
*   **Count:** Number of records (e.g., Number of Commitments).
*   **Avg:** Average value.
*   **Min / Max:** The lowest or highest value.
*   **Latest:** The value from the most recently created record (e.g., Latest KYC Status).
*   **List:** A comma-separated list of all unique values.

---

## 4. Filtering and Sorting

### Applying Filters
You can filter both the primary table and the joined tables independently.
1.  In the **Filters** section (right panel), click **Add** under the relevant table.
2.  **Field:** Select the field to filter by.
3.  **Operator:** Choose an operator (e.g., *equals*, *contains*, *greater than*, *any of*).
4.  **Value:** Enter the filter value. 
    *   *Tip:* Use **"any of"** with commas (e.g., `Individual, Institutional`) to filter for multiple values at once.
5.  Click **Save All Filters** to apply your changes.

### Sorting
In the **Default Sorting** section (right panel), select a column and a direction (Ascending ↑ or Descending ↓). This determines the default order of rows in your export.

---

## 5. Advanced: Pivot Tables
The Report Builder supports "Pivoting" for joined relations, allowing you to turn row data into columns (e.g., showing commitment amounts broken down by Fund name as separate columns).

1.  In the **Relations & Joins** section, find the joined table you want to pivot.
2.  **Category:** Select the field that will become the new column headers (e.g., *Fund Name*).
3.  **Value:** Select the numeric field to display (e.g., *Amount*).
4.  **Aggregate:** Choose how to calculate the value (usually *Sum*).
5.  Click **Apply**.

---

## 6. Preview and Export

### Data Preview
Click the **Preview** button at the top right (or **Refresh Preview** at the bottom) to see the first 50 rows of your report. This helps you verify your configuration before exporting.
*   *Note:* Rows from the primary table that have no matching data in a joined table will appear with `0` or blank values (this is a "Left Join").

### Exporting to Excel
1.  Click **Export XLSX** at the top right.
2.  The system will generate a well-formatted `.xlsx` file.
3.  For large reports, the generation happens in the background, and you will receive a notification when your download is ready.

---

## Tips for Success
*   **Start Small:** Add a few columns and preview frequently to ensure the data looks as expected.
*   **Check Aggregates:** If a number looks wrong, double-check if you are using *Sum* vs. *Count*.
*   **Use Search:** The system has hundreds of available fields; the search bar in the palette is your best friend.
*   **Saved Reports:** All builder reports are saved automatically. You can return to the Reports list at any time to edit or re-run them.
