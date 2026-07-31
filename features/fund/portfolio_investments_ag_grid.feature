@javascript
Feature: Portfolio Investments AG Grid health
  The AG Grid on the Portfolio Investments page depends on CDN-hosted
  CSS (core ag-grid.css + the quartz theme) whose version must stay
  compatible with the pinned AG Grid JS. A bad pin (e.g. a 404ing
  ag-theme-quartz.css) leaves the grid *functional* but visually
  broken: no header styling, missing icons, collapsed layout.
  So these scenarios assert that the stylesheets actually loaded and
  their rules were applied — not merely that the grid DOM exists.

  Scenario: AG grid renders with its stylesheets loaded and theme applied
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=XYZ;currency=INR"
    Given there is a fund "name=Test fund;currency=INR" for the entity
    Given there are "3" portfolio investments "quantity=200"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    And every AG grid stylesheet on the page should have loaded
    And the AG grid structural CSS should be applied
    And the AG grid quartz theme CSS should be applied
    And the AG grid icons should use the AG icon font
