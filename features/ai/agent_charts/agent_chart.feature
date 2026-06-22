Feature: Agent Charts
  As a fund manager
  I want to create and manage AI-generated Chart.js charts
  So that I can visualise KPI data for my portfolio companies

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=TechCorp;category=Portfolio Company"
    And portfolio company is added to list of companies

  # ── CRUD ────────────────────────────────────────────────────────────────────

  Scenario: View the agent charts index
    Given there is an agent chart "title=Revenue Chart;prompt=Plot revenue over time;tag_list=saas"
    When I visit the agent charts index
    Then I should see "Revenue Chart" in the agent charts table
    And I should see "Plot revenue over time" in the agent charts table

  Scenario: Create an agent chart with KPIs
    When I visit the new agent chart page
    And I fill in the agent chart form with:
      | title       | Cost vs Revenue         |
      | prompt      | Bar chart: cost vs rev  |
    And I select KPI "Revenue" for the agent chart
    And I submit the agent chart form
    Then I should see "Agent chart was successfully created"
    And the agent chart status should be "Draft"

  Scenario: Edit an agent chart
    Given there is an agent chart "title=Old Title;prompt=Old prompt"
    When I visit the edit page for that agent chart
    And I update the title to "New Title"
    And I submit the agent chart form
    Then I should see "Agent chart was successfully updated"
    And I should see "New Title" on the agent chart show page

  Scenario: Delete an agent chart
    Given there is an agent chart "title=Doomed Chart;prompt=Delete me"
    When I visit the show page for that agent chart
    And I delete the agent chart
    Then I should see "Agent chart was successfully destroyed"
    And I should not see "Doomed Chart" in the agent charts table

  # ── Chart generation ─────────────────────────────────────────────────────────

  Scenario: Generate a chart spec from KPI data (LLM mocked)
    Given there is an agent chart "title=KPI Chart;prompt=Plot revenue;kpi_names=Revenue"
    And KPI data "name=Revenue;value=500" exists for the portfolio company
    And the LLM is mocked to return a valid bar chart spec
    When I generate the chart spec for the portfolio company
    Then the agent chart status should be "Ready"
    And the spec should have a string key for the portfolio company id

  Scenario: View rendered chart for a portfolio company
    Given there is an agent chart "title=Rendered Chart;prompt=Show revenue" with a saved spec for the portfolio company
    When I visit the show page for that agent chart
    And I select the portfolio company from the Charts dropdown
    Then I should see the chart canvas rendered on the page
    And the chart controller should have the spec value set

  Scenario: Chart height is applied to the canvas
    Given there is an agent chart "title=Tall Chart;prompt=Show revenue;chart_height=700" with a saved spec for the portfolio company
    When I visit the show page for that agent chart
    And I select the portfolio company from the Charts dropdown
    Then the chart container should have height value "700"

  Scenario: Chart generation failure sets status to failed
    Given there is an agent chart "title=Broken Chart;prompt=Plot revenue;kpi_names=Revenue"
    And KPI data "name=Revenue;value=500" exists for the portfolio company
    And the LLM is mocked to raise an error
    When I generate the chart spec for the portfolio company
    Then the agent chart status should be "Failed"
    And the agent chart error should not be blank

  # ── Tag filtering ─────────────────────────────────────────────────────────────

  Scenario: Agent chart job uses tag_list to match portfolio companies
    Given there is an agent chart "title=Tagged Chart;prompt=Plot revenue;tag_list=saas;kpi_names=Revenue"
    And the portfolio company has tag "saas"
    And KPI data "name=Revenue;value=500" exists for the portfolio company
    And the LLM is mocked to return a valid bar chart spec
    When the agent chart job runs for all tagged portfolio companies
    Then the agent chart should have a spec for the portfolio company
