@guide_faqs
Feature: FAQ Manager — support-managed user-guide FAQs and chatbot guide search
  As a CapHive support user
  I want to manage user-guide FAQs in the app and have the guide pages and the chatbot use them
  So that answers can be corrected and added without a code change or deploy

  # See docs/ai/guide_faq_search_prd.md. Elasticsearch is bypassed in tests, so search runs on
  # GuideSearch's database backend, which applies the same synonyms and strong-match rule.

  Background:
    Given there is a user "first_name=Faq;last_name=Staff;email=faq.staff@caphive.com" for an entity "name=FAQ Test Co;entity_type=Investment Fund"

  # ── Access ────────────────────────────────────────────────────────────────

  Scenario: A support user can open FAQ Manager
    Given the user has the role "support"
    When the user requests "/faq_entries"
    Then the docs response should be successful
    And the docs response body should contain "FAQ Manager"

  Scenario: A support user can open every FAQ Manager screen
    Given the user has the role "support"
    And a "published" FAQ on guide "tracking_currency_guide" asking "Where are exchange rates kept?" with answer "Company menu → [**Exchange Rates**](/exchange_rates)."
    And a search synonym "fx, exchange rate"
    When the user requests "/faq_entries/new?question=How+do+I+upload+rates%3F"
    Then the docs response should be successful
    And the docs response body should contain "How do I upload rates?"
    When the user requests the FAQ page for "Where are exchange rates kept?"
    Then the docs response should be successful
    And the docs response body should contain "Exchange Rates"
    When the user requests the edit page for the FAQ "Where are exchange rates kept?"
    Then the docs response should be successful
    When the user requests "/guide_search_synonyms"
    Then the docs response should be successful
    And the docs response body should contain "fx, exchange rate"
    When the user requests "/guide_search_misses"
    Then the docs response should be successful
    When the user requests "/faq_entries.xlsx"
    Then the docs response should be successful

  Scenario: A company user without a staff role cannot open FAQ Manager
    When the user requests "/faq_entries"
    Then the docs response should redirect to "/"

  Scenario: A support user impersonating a customer cannot open FAQ Manager
    When a support user impersonates the user and requests "/faq_entries"
    Then the impersonation should be active in the session
    And the docs response should redirect to "/"

  Scenario: A company user can browse every FAQ on one page
    Given a "published" FAQ on guide "tracking_currency_guide" asking "What is a tracking currency?" with answer "A second reference currency for a fund, set on [**Funds**](/funds)."
    When the user requests "/faqs"
    Then the docs response should be successful
    And the docs response body should contain "What is a tracking currency?"
    And the docs response body should contain "Tracking Currency"

  # ── Lifecycle and validation ──────────────────────────────────────────────

  Scenario: A draft FAQ does not show on the guide page until it is published
    Given a "draft" FAQ on guide "tracking_currency_guide" asking "Where do I set the tracking currency?" with answer "Open [**Funds**](/funds), pick the fund and click **Edit**."
    When the guide "tracking_currency_guide" is rendered
    Then the rendered guide should not contain "Where do I set the tracking currency?"
    When the FAQ "Where do I set the tracking currency?" is published
    And the guide "tracking_currency_guide" is rendered
    Then the rendered guide should contain "Where do I set the tracking currency?"
    And the rendered guide should have 1 FAQ accordion item
    And the rendered FAQ item should be anchored to its FAQ id

  Scenario: Publishing is refused when the answer quotes a path that does not route
    Given a "draft" FAQ on guide "tracking_currency_guide" asking "Where is the old page?" with answer "Go to [the old page](/no_such_page_anywhere)."
    When the FAQ "Where is the old page?" is published
    Then the FAQ "Where is the old page?" should still be a draft
    And the FAQ "Where is the old page?" should have the error "unroutable link /no_such_page_anywhere"

  Scenario: Publishing is refused when the answer shows a raw app path instead of a link
    Given a "draft" FAQ on guide "tracking_currency_guide" asking "Where are the rates?" with answer "They are at `/exchange_rates`."
    When the FAQ "Where are the rates?" is published
    Then the FAQ "Where are the rates?" should still be a draft
    And the FAQ "Where are the rates?" should have the error "shows the raw path /exchange_rates"

  Scenario: A public FAQ is allowed only on a guide readable without a login
    When a "draft" FAQ is saved on guide "tracking_currency_guide" with audience "public"
    Then the FAQ should be invalid with an error on "audience"

  Scenario: The nightly verification flags a published FAQ whose path stopped routing
    Given a "published" FAQ on guide "tracking_currency_guide" asking "Where are exchange rates?" with answer "Company menu → [**Exchange Rates**](/exchange_rates)."
    And the FAQ "Where are exchange rates?" answer is changed to "See [rates](/retired_exchange_rates_page)." without validation
    When the FAQ verification job runs
    Then the FAQ "Where are exchange rates?" should need verification

  # ── Chatbot search ────────────────────────────────────────────────────────

  Scenario: The chatbot's guide search returns a published FAQ and records a strong hit
    Given a "published" FAQ on guide "capital_calls_user_guide" asking "How do I record a payment from an investor?" with answer "Open the remittance and click **New Payment** on its **Payments** tab."
    When the guide search tool is called with keywords "record payment investor"
    Then the guide search output should contain "How do I record a payment from an investor?"
    And the guide search should record a hit that is strong

  Scenario: A synonym managed by support finds an FAQ worded differently
    Given a "published" FAQ on guide "capital_calls_user_guide" asking "How do I create a capital call?" with answer "On the fund's **Calls** tab click **New Call**."
    And a search synonym "tranche, capital call"
    When the guide search tool is called with keywords "tranche"
    Then the guide search output should contain "How do I create a capital call?"

  Scenario: A search matching only one of three words is recorded as a weak hit
    Given a "published" FAQ on guide "capital_calls_user_guide" asking "How do I create a capital call?" with answer "On the fund's **Calls** tab click **New Call**."
    When the guide search tool is called with keywords "capital zebra spaceship"
    Then the guide search should record a hit that is not strong

  # ── Spreadsheet ───────────────────────────────────────────────────────────

  Scenario: Exported FAQs can be edited in the spreadsheet and imported back
    Given a "published" FAQ on guide "tracking_currency_guide" asking "What is a tracking currency?" with answer "A second reference currency for a fund."
    When the FAQs are exported to a spreadsheet
    And the spreadsheet answer for "What is a tracking currency?" is changed to "A second reference currency that CapHive converts every amount into."
    And the spreadsheet gets a new row on guide "tracking_currency_guide" asking "Can investors see tracking figures?" with answer "Yes, on a distribution payment's page."
    And the spreadsheet is imported
    Then the import should report 1 created, 1 updated and 0 errors
    And the FAQ "What is a tracking currency?" should have answer "A second reference currency that CapHive converts every amount into."
    And the FAQ "Can investors see tracking figures?" should be a draft
