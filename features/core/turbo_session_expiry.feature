Feature: Turbo frame session expiry and error handling
  When a session expires, or a turbo frame response is broken,
  the user must be informed instead of being left with a silently dead frame.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"

  @javascript
  Scenario: Expired session during a turbo frame load redirects to the sign in page
    When I visit the entity dashboard
    And my session has expired
    And a turbo frame on the page loads "/entities/dashboard?from_frame=1"
    Then I should be redirected to the sign in page with a session message

  @javascript
  Scenario: Re-authenticating after a frame session expiry returns to the original page
    When I visit the entity dashboard
    And my session has expired
    And a turbo frame on the page loads "/entities/dashboard?from_frame=1"
    Then I should be redirected to the sign in page with a session message
    When I fill and submit the login page
    Then I should be back on the entity dashboard page

  @javascript
  Scenario: A turbo frame response without a matching frame shows a friendly error card
    When I visit the entity dashboard
    And a turbo frame on the page loads "/entities/dashboard"
    Then I should see the section load error card
    And I pause so the error card can be seen
    When I click retry on the section load error card
    Then a fresh section load error card replaces the stale one
