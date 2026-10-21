# LP mobile app — one app for every environment and region, and one fund manager at a time.
# Worked examples: openspec/changes/lp-mobile-multi-site/business-rules.md
#
# The suite stands in for two regions in one process (cross_region_steps.rb): a link is minted
# with CURRENT_SITE=IN and redeemed after switching CURRENT_SITE to US.
@cross-region-cache @cross-region-issuance
Feature: LP mobile app across regions and fund managers

  Background:
    Given the regions are "IN, US"
    And the current region is "IN"
    And a mobile investor "rahul@sharmafo.in" of "Sharma Family Office" with fund manager "Arka Capital"
    And Arka Growth Fund I is set up for Sharma Family Office
    And "rahul@sharmafo.in" is signed in on the phone "iPhone 15"

  # ── Sites (design card ①) ──────────────────────────────────────────────────

  # MS-H1 — Happy path: before sign-in, the app asks the environment which regions it has
  Scenario: The environment lists its regions
    When a phone that is not signed in asks "/api/mobile/v1/sites"
    Then the phone gets the status 200
    And the phone sees the sites "IN India https://app.caphive.test; US US https://app.caphive.us.test"
    And the JSON at "current" is "IN"

  # ── Region switch (design card ②) ──────────────────────────────────────────

  # MS-H2 — Happy path: /me offers the regions the user belongs to
  Scenario: Regions offered to a two-region user
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone is offered the regions "IN, US"

  # MS-E2 — Edge case: a one-region user is offered only that region (the app hides the switch)
  Scenario: One-region user
    Given "rahul@sharmafo.in" belongs to the regions "IN"
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone is offered the regions "IN"

  # MS-H3 — Happy path: switch to US without a password or code; the phone is registered in US
  Scenario: Switch region
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    When the phone "iPhone 15" asks for a link to the region "US"
    Then the phone gets the status 201
    And the JSON at "url" is "https://app.caphive.us.test"
    When the current region is "US"
    And the phone "iPhone 15" redeems the region link
    Then the phone gets a session
    And "rahul@sharmafo.in" has a live phone "iPhone 15" in the region "US"

  # MS-X1 — Error case: a region the user does not belong to is refused
  Scenario: Region the user does not belong to
    Given "rahul@sharmafo.in" belongs to the regions "IN"
    When the phone "iPhone 15" asks for a link to the region "US"
    Then the phone gets the status 422
    And the phone gets the error "region_unavailable"

  # MS-E3 — Edge case: switching to the region the phone is already on is refused
  Scenario: Same region
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    When the phone "iPhone 15" asks for a link to the region "IN"
    Then the phone gets the error "region_unavailable"

  # MS-X2 — Error case: a website region-switch link cannot be redeemed as a phone session
  Scenario: Website link refused by the phone API
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    And the phone "iPhone 15" holds a website region-switch link for "US"
    When the current region is "US"
    And the phone "iPhone 15" redeems the region link
    Then the phone gets the status 401
    And the phone gets the error "region_switch_failed"

  # MS-X4 — Error case: a link for US redeemed in IN (wrong destination) is refused
  Scenario: Link redeemed in the wrong region
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    When the phone "iPhone 15" asks for a link to the region "US"
    And the phone "iPhone 15" redeems the region link
    Then the phone gets the error "region_switch_failed"

  # MS-X5 — Error case: a link works once
  Scenario: Link used twice
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    When the phone "iPhone 15" asks for a link to the region "US"
    And the current region is "US"
    And the phone "iPhone 15" redeems the region link
    Then the phone gets a session
    When the phone "iPhone 15" redeems the region link
    Then the phone gets the status 401
    And the phone gets the error "challenge_spent"

  # MS-E4 — Edge case: a user deactivated in the target region is not signed in there
  Scenario: Deactivated in the target region
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    When the phone "iPhone 15" asks for a link to the region "US"
    And the current region is "US"
    And the investor user "rahul@sharmafo.in" is deactivated
    And the phone "iPhone 15" redeems the region link
    Then the phone gets the error "invalid_credentials"

  # MS-X3 — Error case: without the cross-region secret there is no switch
  Scenario: Cross-region secret missing
    Given "rahul@sharmafo.in" belongs to the regions "IN,US"
    And this region has no inter-region secret configured
    When the phone "iPhone 15" asks for a link to the region "US"
    Then the phone gets the error "region_unavailable"

  # ── One fund manager at a time (design card ③) ─────────────────────────────

  # MF-H3 — Happy path: /me lists the fund managers, sorted by name
  Scenario: Fund managers offered
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone is offered the fund managers "Arka Capital, Beta Partners"

  # MF-H4 — Happy path: /me gives each fund manager's logo for the app's branding; none without one
  Scenario: Fund manager logos
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    And "Arka Capital" has uploaded a logo
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the fund manager "Arka Capital" has a logo link
    And the fund manager "Beta Partners" has no logo link

  # MF-H1 — Happy path: with no pick, Home shows the first fund manager only — never both
  Scenario: Home defaults to the first fund manager
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone sees fund cards from "Arka Capital"
    And the Home is for the fund manager "Arka Capital"

  # MF-H2 — Happy path: picking Beta shows only Beta's cards and To do
  Scenario: Home for the picked fund manager
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    When the phone "iPhone 15" opens Home for the fund manager "Beta Partners"
    Then the phone sees fund cards from "Beta Partners"
    And the phone's To do is empty
    And the Home is for the fund manager "Beta Partners"

  # MF-E1 — Edge case: a fund manager the user has no access to falls back to the first
  Scenario: Pick without access falls back
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    And a fund manager "Gamma Ventures" the investor has no access to
    When the phone "iPhone 15" opens Home for the fund manager "Gamma Ventures"
    Then the phone sees fund cards from "Arka Capital"
    And the Home is for the fund manager "Arka Capital"

  # MF-E2 — Edge case: a user with no approved fund manager gets no fund manager and an empty Home
  Scenario: No fund manager
    Given Rahul's investor access to Arka Capital is not approved
    When the phone "iPhone 15" requests "/api/mobile/v1/home"
    Then the phone gets the status 200
    And the JSON at "fund_manager_id" is ""

  # MF-H4 — Happy path: Documents list only the picked fund manager's documents
  Scenario: Documents for the picked fund manager
    Given Sharma Family Office has a commitment of 20000000 to "Beta Opportunities" managed by "Beta Partners"
    And the commitment has a document "Arka Statement"
    And the Beta commitment has a document "Beta Statement"
    When the phone "iPhone 15" opens Documents for the fund manager "Beta Partners"
    Then the phone's document list includes "Beta Statement"
    And the phone's document list does not include "Arka Statement"

  # MF-H5 — Happy path: an alert and its push carry the fund manager and region they are about
  Scenario: Alerts carry their fund manager
    Given "rahul@sharmafo.in" has an unread notification for Capital Call 3
    When the phone "iPhone 15" requests "/notifications.json?all=1"
    Then the first alert's sender is "Arka Capital"
