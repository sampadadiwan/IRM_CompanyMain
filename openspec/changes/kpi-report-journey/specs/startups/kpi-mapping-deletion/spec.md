# Spec Delta

## Purpose

Lets a fund delete a KPI mapping that KPIs already use, after a warning that shows what will be lost,
instead of failing with an error page.

## ADDED Requirements

### Requirement: Deleting an unused mapping
A KPI mapping that no KPI uses SHALL be deleted as before, without a warning popup.

#### Scenario: Unused mapping
- **WHEN** an admin deletes the mapping "Headcount" which no KPI uses
- **THEN** it is deleted and the KPI mappings tab shows the usual success message

### Requirement: A mapping with children cannot be deleted
A KPI mapping that is the parent of other mappings SHALL NOT be deleted, whether or not KPIs use it. The
Delete button SHALL be disabled with a tooltip naming the children, and a delete request SHALL be refused
with "Move or delete <children> first", deleting nothing.

#### Scenario: Parent mapping
- **WHEN** an admin tries to delete "Net Sales", the parent of "Enterprise" and "Retail"
- **THEN** nothing is deleted and the page says "Move or delete Enterprise, Retail first"

### Requirement: Warning before deleting a mapping in use
Deleting a KPI mapping that KPIs use SHALL first show a confirmation popup stating the number of KPIs and
periods that will be deleted, how many of them are approved, every computed mapping of the same portfolio
company whose formula uses the mapping's name, and that the delete cannot be undone.

#### Scenario: Popup shows counts
- **WHEN** an admin clicks Delete on "Revenue", used by 214 KPIs across 31 periods, 180 approved, and "ARPC" has formula "Revenue/Cycles"
- **THEN** the popup says "214 KPIs across 31 periods (180 approved)", "ARPC uses Revenue" and "Cannot be undone"

#### Scenario: Cancel
- **WHEN** the admin cancels the popup
- **THEN** nothing is deleted

### Requirement: Deleting a mapping in use
Confirming SHALL delete the mapping's KPIs and then the mapping in one transaction, in batches, recompute
percentage changes and auto-filled values for the portfolio company in the background, and re-evaluate the
portfolio company's open KPI journeys. A failure SHALL delete nothing and show an error message, never an
error page.

#### Scenario: Confirmed delete
- **WHEN** the admin confirms deleting "Revenue"
- **THEN** the mapping and its 214 KPIs are gone, recomputation is queued and Acme's open journeys re-evaluate

#### Scenario: Last mapping deleted
- **WHEN** the deleted mapping was Acme's last non-computed mapping
- **THEN** Acme's open KPI journeys move back to "Set up KPI mappings"

#### Scenario: Delete fails
- **WHEN** the delete raises a database error part-way
- **THEN** no KPI or mapping is deleted and the page shows "Could not delete Revenue — nothing was changed"
