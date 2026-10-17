# LP mobile app — opening a website page from the app, already signed in (design card ⑦).
# Worked examples: openspec/changes/lp-mobile-app/design.md#worked-examples
@cross-region-cache @rack_test
Feature: LP mobile app website hand-off

  Background:
    Given a mobile investor "rahul@sharmafo.in" of "Sharma Family Office" with fund manager "Arka Capital"
    And Arka Growth Fund I is set up for Sharma Family Office
    And "rahul@sharmafo.in" is signed in on the phone "iPhone 15"

  # H13 — Happy path: a page the app has no screen for opens on the website, signed in
  Scenario: A website page opens signed in
    When the phone "iPhone 15" asks for a website link to the Arka commitment page
    Then the phone gets the status 201
    When I open the website link
    Then I am on the Arka commitment page

  # E23 — Edge case: only pages of this site can be opened
  Scenario Outline: Off-site paths are refused
    When the phone "iPhone 15" posts to "/api/mobile/v1/web_handoffs" with:
      """
      { "path": "<path>" }
      """
    Then the phone gets the status 422
    And the phone gets the error "invalid_path"

    Examples:
      | path                |
      | //evil.com          |
      | https://evil.com/x  |
      | /no/such/page/here  |

  # E36 — Edge case: the page itself still applies the website's own access checks
  Scenario: A link to a page the investor may not see
    Given Kapoor Holdings has a capital call in Arka Growth Fund I
    When the phone "iPhone 15" asks for a website link to Kapoor's capital call page
    And I open the website link
    Then I should see "Access Denied"

  # X12 — Error case: a link works once
  Scenario: A link opened twice
    When the phone "iPhone 15" asks for a website link to the Arka commitment page
    And I open the website link
    And I sign out of the website
    And I open the website link
    Then I am on the website sign-in page

  # X13 — Error case: a link expires after 5 minutes
  Scenario: An expired link
    When the phone "iPhone 15" asks for a website link to the Arka commitment page
    And 5 minutes and 1 seconds pass
    And I open the website link
    Then I am on the website sign-in page

  # X16 — Error case: a signed-out phone cannot ask for a link
  Scenario: Signed-out phone
    Given the phone "iPhone 15" was signed out on the website
    When the phone "iPhone 15" asks for a website link to the Arka commitment page
    Then the phone gets the status 401
