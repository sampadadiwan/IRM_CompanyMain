@website_leads
Feature: Capturing demo requests from the public website
  As CapHive
  I want the demo form on caphive.com to post into our own database
  So that we see a prospect the moment they ask, instead of hoping they send an email

  # This is the only unauthenticated, CSRF-exempt write endpoint in the app, reachable
  # cross-origin from a static site we control. The coverage below is therefore weighted
  # towards the ways it can be abused or misconfigured, not just the happy path.
  #
  # See docs/technical/website_lead_capture.md.

  Background:
    Given the website hosts are "caphive.com,www.caphive.com"

  # ── The lead arrives ──────────────────────────────────────────────────────

  Scenario: A valid multipart submission is stored and announced
    When the website submits a demo request from "https://caphive.com" with:
      | name    | Nadia Okonkwo                                      |
      | firm    | Meridian Capital                                   |
      | email   | nadia@meridiancapital.example                      |
      | role    | CFO or Finance                                     |
      | message | Four currencies and a close that takes three weeks. |
    Then the lead response status should be 200
    And 1 website lead should exist
    And a website lead should exist for "nadia@meridiancapital.example"
    And a lead notification email should have been delivered

  Scenario: The notification reaches the commercial mailbox and replies to the prospect
    When the website submits a demo request from "https://caphive.com" with:
      | name    | Nadia Okonkwo                                      |
      | firm    | Meridian Capital                                   |
      | email   | nadia@meridiancapital.example                      |
      | role    | CFO or Finance                                     |
      | message | Four currencies and a close that takes three weeks. |
    Then the lead notification should have been sent to "hello@caphive.com"
    And the lead notification should reply to "nadia@meridiancapital.example"
    And the notification should contain "Nadia Okonkwo"
    And the notification should contain "Meridian Capital"
    And the notification should contain "nadia@meridiancapital.example"
    And the notification should contain "CFO or Finance"
    And the notification should show the submission date as Mon dd, yyyy

  Scenario: The prospect's own words reach the notification in full
    When the website submits a demo request from "https://caphive.com" with:
      | name    | Nadia Okonkwo                                      |
      | firm    | Meridian Capital                                   |
      | email   | nadia@meridiancapital.example                      |
      | message | Four currencies and a close that takes three weeks. |
    Then the notification should contain "Four currencies and a close that takes three weeks."

  Scenario: Campaign attribution is persisted
    When the website submits a demo request from "https://caphive.com" with:
      | name         | Nadia Okonkwo                 |
      | firm         | Meridian Capital              |
      | email        | nadia@meridiancapital.example |
      | utm_source   | linkedin                      |
      | utm_medium   | social                        |
      | utm_campaign | us-launch                     |
    Then the lead response status should be 200
    And the stored lead should have "utm_source" set to "linkedin"
    And the stored lead should have "utm_medium" set to "social"
    And the stored lead should have "utm_campaign" set to "us-launch"

  Scenario: The page that produced the lead is recorded
    When the website submits a demo request from "https://caphive.com" with:
      | name         | Nadia Okonkwo                 |
      | firm         | Meridian Capital              |
      | email        | nadia@meridiancapital.example |
      | _source_page | portfolio-kpis-at-scale.html  |
    Then the stored lead should have "landing_page" set to "portfolio-kpis-at-scale.html"

  Scenario: The submitting IP is recorded for abuse control
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the stored lead should have a request IP recorded

  # ── Validation ────────────────────────────────────────────────────────────

  Scenario: A malformed email is rejected without creating a row
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo    |
      | firm  | Meridian Capital |
      | email | not-an-address   |
    Then the lead response status should be 422
    And 0 website leads should exist
    And no lead notification email should have been delivered

  Scenario: A missing name is rejected
    When the website submits a demo request from "https://caphive.com" with:
      | name  |                               |
      | email | nadia@meridiancapital.example |
    Then the lead response status should be 422
    And 0 website leads should exist

  # An oversized message must come back as a clean 422, never a 500 — the field is
  # free text from strangers and is the obvious thing to throw junk at.
  Scenario: An oversized message is rejected cleanly
    When the website submits a demo request from "https://caphive.com" with a 6000-character message
    Then the lead response status should be 422
    And 0 website leads should exist

  # ── Spam controls ─────────────────────────────────────────────────────────

  # A filled honeypot returns 200 and stores nothing. Answering with an error would
  # tell the bot exactly which field to leave alone next time.
  Scenario: A filled honeypot is silently discarded
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
      | _hp   | http://spam.example           |
    Then the lead response status should be 200
    And 0 website leads should exist
    And no lead notification email should have been delivered

  Scenario: A form returned faster than a human could read it is silently discarded
    Given the form was rendered 0 seconds ago
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response status should be 200
    And 0 website leads should exist

  # A cached page or partially-blocked JS sends no stamp at all. That must be
  # accepted: silently dropping a real lead is the failure this feature exists to end.
  Scenario: A submission with no render stamp is accepted
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
      | _ts   |                               |
    Then the lead response status should be 200
    And 1 website lead should exist

  @rack_attack
  Scenario: A sixth submission within the hour from one IP is throttled
    When the website submits 6 demo requests from IP "203.0.113.7" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the last of those responses should be throttled

  # ── CORS ──────────────────────────────────────────────────────────────────

  Scenario: An allowed origin gets its own origin echoed back, and never credentials
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response should allow the origin "https://caphive.com"
    And the lead response should never allow credentials
    And the lead response should vary on origin

  # An unlisted origin gets no CORS header. The row may still be written — the browser
  # sends the request either way — but the calling script can never read the response,
  # which is what stops a hostile page from using this endpoint as its own backend.
  Scenario: An unlisted origin gets no permissive CORS header
    When the website submits a demo request from "https://evil.example" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response should not allow any origin

  Scenario: The other stack's website is not automatically trusted
    Given the website hosts are "caphive.us,www.caphive.us"
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response should not allow any origin

  # Development serves the site at caphive.localhost:3001 and the app at
  # localhost:3001, so the Origin carries a port. Matching whole origin strings
  # would work in production and fail the first time anyone tested locally.
  Scenario: An allowed host is still allowed when the origin carries a port
    Given the website hosts are "caphive.localhost,www.caphive.localhost"
    When the website submits a demo request from "http://caphive.localhost:3001" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response should allow the origin "http://caphive.localhost:3001"

  Scenario: A malformed origin header is refused, not crashed on
    When the website submits a demo request from "http://[not a url" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response status should be 200
    And the lead response should not allow any origin

  Scenario: With no website hosts configured, no origin is trusted
    Given no website hosts are configured
    When the website submits a demo request from "https://caphive.com" with:
      | name  | Nadia Okonkwo                 |
      | firm  | Meridian Capital              |
      | email | nadia@meridiancapital.example |
    Then the lead response should not allow any origin

  Scenario: The preflight answers an allowed origin
    When the website preflights the demo request from "https://www.caphive.com"
    Then the lead response status should be 204
    And the lead response should allow the origin "https://www.caphive.com"

  # ── Who can read the leads ────────────────────────────────────────────────

  Scenario: A support user can read the leads
    Given there is a user "first_name=Lead;last_name=Staff;email=lead.staff@caphive.com" for an entity "name=Website Leads Test Co;entity_type=Investment Fund"
    And the user has the role "support"
    And a website lead exists from "Nadia Okonkwo" at "Meridian Capital"
    When the signed-in user requests the website leads index
    Then the leads screen should be visible
    And the leads screen should show "Meridian Capital"

  Scenario: A support user can read one lead in full
    Given there is a user "first_name=Lead;last_name=Staff;email=lead.staff@caphive.com" for an entity "name=Website Leads Test Co;entity_type=Investment Fund"
    And the user has the role "support"
    And a website lead exists from "Nadia Okonkwo" at "Meridian Capital"
    When the signed-in user requests that website lead
    Then the leads screen should be visible
    And the leads screen should show "We close 40 SPVs a year and the close is manual."

  # These records have no entity, so tenancy cannot gate them and role is the only
  # boundary. An ordinary customer reaching this screen would be reading our pipeline.
  Scenario: An ordinary user with no staff role is denied
    Given there is a user "first_name=Ordinary;last_name=Customer;email=ordinary.customer@example.com" for an entity "name=Website Leads Customer Co;entity_type=Investment Fund"
    And a website lead exists from "Nadia Okonkwo" at "Meridian Capital"
    When the signed-in user requests the website leads index
    Then the leads screen should be denied

  Scenario: An anonymous visitor cannot read the leads
    Given a website lead exists from "Nadia Okonkwo" at "Meridian Capital"
    When an anonymous visitor requests the website leads index
    Then the leads screen should be denied
