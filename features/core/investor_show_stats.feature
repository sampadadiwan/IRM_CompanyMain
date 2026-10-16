Feature: Investor show page stat cards
  The stakeholder page summarises its tabs in one row of cards above them, and each card opens
  the tab it summarises. Portfolio companies get their holding figures instead of commitments.

# S1 — Edge case: commitments in two fund currencies are shown per currency (Cr for INR, M otherwise), never converted or added
Scenario: Fund stakeholder's cards show commitments per currency and open their tabs
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  And there is a stakeholder with commitments of "100000000" INR and "2000000" USD
  And the stakeholder has 1 open task
  When I visit the stakeholder's page
  Then the "Committed" stat card shows "₹10.00 Cr" and "$2.00 M"
  And the "Open Tasks" stat card shows "1"
  When I click the "Committed" stat card
  Then the "commitments-tab" tab is open
  When I click the "Open Tasks" stat card
  Then the "tasks-tab" tab is open

# S2 — Edge case: a portfolio company shows holding cards, not commitments; never valued shows "-"
Scenario: Portfolio company's cards show its holdings and open their tabs
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  And there is a portfolio company stakeholder
  And the stakeholder has 1 open task
  When I visit the stakeholder's page
  Then I should see stat cards "Bought Amount, FMV, Income, Last Valued, Open Tasks"
  And I should not see a "Committed" stat card
  And the "Last Valued" stat card shows "-"
  When I click the "Open Tasks" stat card
  Then the "tasks-tab" tab is open
