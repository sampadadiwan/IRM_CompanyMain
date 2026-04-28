# Deals Management User Guide

This guide provides a comprehensive overview of how to manage investors and track fundraising progress using the IRM Deals interface.

---

## 1. Overview
The **Deals List View** is your central command for tracking a fundraising deal. It combines high-level analytics, interactive visualizations, and a powerful data grid for granular management of your investor pipeline.

## 2. Real-Time Analytics
At the top of the page, four interactive cards provide a snapshot of the deal's health. You can click these cards to immediately filter the investor grid below:

*   **Total Target:** Shows the overall fundraising goal. Click to clear all filters and see all investors.
*   **Committed (Active):** Displays the total amount committed by "Active" investors. Click to filter the grid for all committed/active leads.
*   **Conversion Rate:** The percentage of total leads that have moved to an active/committed status.
*   **Stagnant Leads (>7d):** Identifies leads with no activity for over 7 days. Click this to prioritize follow-ups for stalled deals.

## 3. Interactive Insights (Charts)
The dashboard includes several charts that provide deep visibility into your pipeline. Many of these are **interactive**—clicking a data point will filter the investor grid.

*   **Conversion Funnel:** Visualize how many investors are at each stage (e.g., Interested, In Progress, Committed). Click a stage to see the specific investors in that bucket.
*   **Commitment Velocity:** Track how commitments are growing over time to forecast your closing date.
*   **Weighted Pipeline:** Compare your expected commitment (based on probability) against your target.
*   **Activity Efficiency:** See the average number of days spent on key tasks (e.g., "Initial Call" to "Due Diligence").
*   **Concentration (By Source):** Identify where your leads are coming from (e.g., Referrals, Cold Outreach). Click a source to filter the list.
*   **"Days in Stage" Distribution:** A histogram showing how long leads have been sitting in their current status. Click a bar (e.g., "30+ days") to identify stagnant leads.
*   **Allocation Breakdown:** A pie chart detailing the split between Primary investment, Secondary investment, and Fees.

## 4. The Investor Grid (AG Grid)
The core of the deal management experience is a high-performance grid powered by AG Grid.

### Filtering and Sorting
*   **Column Filters:** Click the filter icon on any column header to apply text, number, date, or set-based filters.
*   **Multi-Column Sort:** Click headers to sort. Hold `Shift` to sort by multiple columns simultaneously.
*   **Group Management:** Drag any column header to the **Group Panel** at the top of the grid to group investors (e.g., group by "Source" or "Lead").

### Inline Editing
You can update almost any field directly within the grid without leaving the page. Changes are saved automatically:
*   **Status:** Change an investor's stage (e.g., move from "Interested" to "Committed").
*   **Tier:** Update the priority level of an investor.
*   **Lead/Advisor/Source:** Assign or update the internal team members or the referral source.
*   **Custom Fields:** If your organization has configured custom fields (e.g., "Investment Thesis"), they appear in the grid and are fully editable.

### Managing Tasks & Health
Each investor has a **Health Score** column, which tracks the completion of mandatory deal activities (tasks).
*   **Health Score Bar:** A visual progress bar (Red/Amber/Green) showing the percentage of completed tasks. Hover over the bar to see a tooltip of **Pending Tasks**.
*   **Activity Columns:** Each task (e.g., "Signed NDA", "Data Room Access") has its own column. You can update these statuses inline to **Complete**, **Incomplete**, or **Skip**. Updating these status values automatically recalculates the investor's Health Score.
*   **Task Automation:** Moving an investor to a new stage (e.g., from "Interested" to "Due Diligence") automatically triggers the creation of associated sub-tasks.
    *   **Source:** These tasks are pulled from the pre-defined activity templates for the deal.
    *   **Assignment:** Tasks are automatically assigned to the user who moved the investor to the new stage, with a default due date of 7 days.
    *   **Requirements:** Some activities may require specific documentation to be uploaded before they can be marked as "Complete".
    *   **No Duplicates:** If an investor is moved back to a previous stage and then forward again, the system identifies and skips already existing tasks to prevent clutter.

## 5. Detailed Investor View (Sidepanel)
For a deeper dive into a specific investor:
1.  Click the **Investor Name** in the grid.
2.  A sidepanel will slide out from the right, loading the full investor profile, contact history, and documents via a Turbo Frame. This allows you to review details while keeping your place in the grid.

## 6. Bulk Actions
When you select one or more investors using the checkboxes on the left:
*   **Bulk Nudge:** Trigger a mass notification or reminder to the selected investors (e.g., a "nudge" to complete a signature).
*   **Update Status:** Simultaneously change the status of all selected investors to a new stage (e.g., moving five investors to "Declined" at once).

## 7. Data Export
To take your data offline, click the **Download Excel** button in the header. This will export the current view (including any active filters or grouping) into a formatted `.xlsx` file.
