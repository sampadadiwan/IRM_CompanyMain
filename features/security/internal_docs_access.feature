@internal_docs
Feature: Internal docs viewer access control
  As CapHive
  I want the marketing and strategy documentation browsable only by CapHive staff
  So that pricing bands, the GTM playbook and competitive analysis never reach a customer account

  # This app has real customer logins (GP and LP users), so InternalDocPolicy is the
  # only boundary between a customer account and CapHive's commercial documents.
  # A gap here is a data-exposure bug, not a UX bug — hence the coverage below of
  # the deny paths and the section whitelist, not just the happy path.

  Background:
    Given there is a user "first_name=Docs;last_name=Staff;email=docs.staff@caphive.com" for an entity "name=Internal Docs Test Co;entity_type=Investment Fund"

  # ── Staff can read ────────────────────────────────────────────────────────

  Scenario: A support user sees both sections on the index
    Given the user has the role "support"
    When the user requests "/internal_docs"
    Then the docs response should be successful
    And the docs response body should contain "Marketing"
    And the docs response body should contain "Strategy"

  Scenario: A support user can read a marketing document
    Given the user has the role "support"
    When the user requests "/internal_docs/marketing/us_gtm_zero_budget_notes"
    Then the docs response should be successful

  Scenario: A super user can read a marketing document
    Given the user has the super role granted directly in the database
    When the user requests "/internal_docs/marketing/us_gtm_zero_budget_notes"
    Then the docs response should be successful

  Scenario: A support user can read the parent strategy document the marketing docs link to
    Given the user has the role "support"
    When the user requests "/internal_docs/features/us_gtm"
    Then the docs response should be successful

  # ── Customers cannot ──────────────────────────────────────────────────────

  Scenario: An ordinary user with no staff role is denied
    When the user requests "/internal_docs"
    Then the docs response should redirect to "/"

  Scenario: An investor-role user is denied
    Given the user has the role "investor"
    When the user requests "/internal_docs"
    Then the docs response should redirect to "/"

  Scenario: An anonymous visitor is sent to the login page
    When an anonymous visitor requests "/internal_docs"
    Then the docs response should redirect to "/users/sign_in"

  # The impersonated session is the CUSTOMER's user record with the acting support
  # user recorded on it — the customer never holds the support role themselves.
  # User#support? is true in this state, so a policy written against it would leak
  # CapHive's commercial docs into a customer-facing view.
  Scenario: A session impersonated by support is denied
    Given the user is impersonating a customer
    Then the user should be treated as support by the legacy helper
    When the user requests "/internal_docs"
    Then the docs response should redirect to "/"

  # ── The whitelist is a security boundary, not just navigation ─────────────

  Scenario Outline: A non-whitelisted tree is unreachable even to staff
    Given the user has the role "support"
    When the user requests "<path>"
    Then the docs response should redirect to "/internal_docs"

    Examples:
      | path                                                         |
      | /internal_docs/technical/internal_docs_viewer                |
      | /internal_docs/security/cybersecurity_risk_management_policy |
      | /internal_docs/dr_drills                                     |
      | /internal_docs/user_guides/ai_features_user_guide            |

  Scenario: A traversal out of a whitelisted section into a protected one is rejected
    Given the user has the role "support"
    When the user requests "/internal_docs/marketing/../technical/internal_docs_viewer"
    Then the docs response should redirect to "/internal_docs"

  Scenario: A traversal out of the docs root entirely is rejected
    Given the user has the role "support"
    When the user requests "/internal_docs/marketing/../../config/database"
    Then the docs response should redirect to "/internal_docs"

  Scenario: A missing document inside a whitelisted section is a redirect, not an error
    Given the user has the role "support"
    When the user requests "/internal_docs/marketing/no_such_document"
    Then the docs response should redirect to "/internal_docs"

  # ── Regressions from sharing WithGuideRendering and retiring /features ─────

  Scenario: The signed-in user guides index still renders
    When the user requests "/user_guides"
    Then the docs response should be successful

  Scenario: A signed-in user guide still renders
    When the user requests "/user_guides/ai_features_user_guide"
    Then the docs response should be successful

  Scenario: A public guide is still readable without a login
    When an anonymous visitor requests "/help/two_factor_authentication_user_guide"
    Then the docs response should be successful

  Scenario: A public guide still refuses an id outside its allowlist
    When an anonymous visitor requests "/help/ai_features_user_guide"
    Then the docs response should redirect to "/users/sign_in"

  Scenario: The retired features index redirects into the internal docs viewer
    Given the user has the role "support"
    When the user requests "/features"
    Then the docs response should redirect to "/internal_docs"

  Scenario: A retired feature document URL redirects to its internal docs equivalent
    Given the user has the role "support"
    When the user requests "/features/us_gtm"
    Then the docs response should redirect to "/internal_docs/features/us_gtm"
