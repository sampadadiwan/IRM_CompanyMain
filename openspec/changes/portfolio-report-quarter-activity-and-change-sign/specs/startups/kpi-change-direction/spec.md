# Spec Delta

## Purpose

Defines the direction of a percentage change when the figure being compared with is negative, so a loss that shrinks reads as a rise and a loss that grows reads as a fall, wherever the system works out such a change.

## ADDED Requirements

### Requirement: A change follows the direction of the movement
The percentage change of a KPI figure (whatever the data type of its mapping, a percentage KPI such as EBITDA % included) against its comparison figure (the previous figure for Month, Quarter and Year, the figure one year earlier for YTD) SHALL be the difference between the two divided by the size of the comparison figure, multiplied by 100. A change SHALL be positive when the figure rose and negative when it fell, whether the comparison figure is positive or negative. The change SHALL be empty when the comparison figure is zero. A comparison figure that is positive SHALL give the same change as before this requirement.

#### Scenario: Positive comparison figure
- **WHEN** the comparison figure is 100 and the figure is 120
- **THEN** the change is 20

#### Scenario: Loss shrinks
- **WHEN** the comparison figure is -100 and the figure is -80
- **THEN** the change is 20

#### Scenario: Loss grows
- **WHEN** the comparison figure is -100 and the figure is -125
- **THEN** the change is -25

#### Scenario: Negative to positive
- **WHEN** the comparison figure is -50 and the figure is 25
- **THEN** the change is 150

#### Scenario: Positive to negative
- **WHEN** the comparison figure is 50 and the figure is -25
- **THEN** the change is -150

#### Scenario: Unchanged figure
- **WHEN** the comparison figure and the figure are both -100
- **THEN** the change is 0

#### Scenario: Comparison figure zero
- **WHEN** the comparison figure is zero
- **THEN** the change is empty

#### Scenario: YTD against a negative year-earlier figure
- **WHEN** the June 2026 YTD is -3.8 and the June 2025 YTD is -3.154 for the same KPI and tag
- **THEN** the June 2026 YTD change is -20.48

#### Scenario: Change too large to store
- **WHEN** the change, rounded to two decimals, is above 9,999.99 in absolute value
- **THEN** the change is empty, as before

#### Scenario: Percentage KPI margin improves
- **WHEN** a percentage KPI (stored as a fraction) is -0.557 and its comparison figure is -0.632
- **THEN** the change is 11.87, the same as for a numeric KPI with the same figures

#### Scenario: Percentage KPI falls
- **WHEN** a percentage KPI is 0.15 and its comparison figure is 0.20
- **THEN** the change is -25

#### Scenario: Percentage KPI against zero
- **WHEN** a percentage KPI is 0.05 and its comparison figure is 0
- **THEN** the change is empty

#### Scenario: Same figures on a numeric KPI
- **WHEN** a numeric KPI is -0.557 and its comparison figure is -0.632
- **THEN** the change is 11.87, as for the percentage KPI

#### Scenario: Percentage KPI year over year
- **WHEN** a percentage KPI's June 2026 YTD is -0.557 and its June 2025 YTD is -0.632
- **THEN** the June 2026 YTD change is 11.87

### Requirement: Stored changes are corrected by the recompute
The existing percentage-change recompute SHALL store changes that follow the direction of the movement. A change SHALL NOT be altered until the recompute runs for its company.

#### Scenario: Recompute corrects a stored change
- **WHEN** a figure with a negative comparison figure holds the change stored under the old rule and the recompute runs
- **THEN** its change follows the direction of the movement

#### Scenario: Not recomputed yet
- **WHEN** the change is shown before the recompute has run
- **THEN** the stored change is shown as it was stored

### Requirement: Thresholds use the corrected change
The KPI grid, the KPI page and the KPI list SHALL colour a change against the KPI mapping's lower and upper thresholds using the change as stored, so a loss that grows (a negative change) is held against the lower threshold.

#### Scenario: Growing loss below the lower threshold
- **WHEN** a figure goes from -100 to -125, its stored change is -25 and the lower threshold is 10
- **THEN** the change shows in red

### Requirement: The report's difference from budget follows the same rules
The portfolio report's difference of an Actual figure from its comparator (`<label>_vs_<tag>_compute_percent`) SHALL follow the same rules as a stored change: the Actual minus the comparator, divided by the size of the comparator, multiplied by 100, and "N/A" when the comparator is zero, for a percentage KPI as for any other. It SHALL be "N/A" when either figure is missing. "Actual as a percentage of the comparator" (`<label>_vs_<tag>_percent`) is a ratio and SHALL NOT change.

#### Scenario: Loss smaller than budgeted
- **WHEN** the Actual is -80 and the Budget is -100
- **THEN** the difference is 20

#### Scenario: Loss larger than budgeted
- **WHEN** the Actual is -125 and the Budget is -100
- **THEN** the difference is -25

#### Scenario: Ratio is not changed
- **WHEN** the Actual is -80 and the Budget is -100
- **THEN** Actual as a percentage of Budget is 80

#### Scenario: Positive budget
- **WHEN** the Actual is 92 and the Budget is 100
- **THEN** the difference is -8, as before

#### Scenario: Percentage KPI against budget
- **WHEN** a percentage KPI's Actual is 0.15 and its Budget is 0.20
- **THEN** the difference is -25

#### Scenario: Comparator missing or zero
- **WHEN** the Actual has no comparator figure, or the comparator is zero
- **THEN** the difference is "N/A"
