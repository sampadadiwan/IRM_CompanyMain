@security @sendgrid_inbound @rack_test
Feature: SendGrid inbound email - 2026-10 security review (H2)
  SendGrid Inbound Parse posts every email sent to an owner address (<type>.<id>@...) to
  /incoming_emails/sendgrid, which files it - with its attachments - against that owner. The webhook
  now proves it is SendGrid with a token from this environment's credentials (refused with 401 once
  SENDGRID_INBOUND_ENFORCE=1, only logged before that), an address may only name a model that takes
  incoming email, attachments are credited to the sender only when the owner's firm knows them, and
  deal-ingest mail without email auth headers is dropped in production. Each refusal is paired with
  the legitimate use that must keep working.
  H2-4 (wrong HMAC address tag) and H2-5 (legacy address after the cutoff) are not here: signed
  address tags and the legacy cutoff are deferred until owner addresses are published again (they
  have not been since 2026-09-25).
  Design and worked examples: docs/security/security_review_2026_10.md#h2--sendgrid-inbound-email

  Background:
    Given there is a user "first_name=Asha" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the investor has a KYC

  # H2-1 — Edge case: with enforcement on, a post without the token is refused and nothing is filed
  Scenario: H2-1 A post without the webhook token is refused once enforced
    Given SendGrid inbound enforcement is on
    When SendGrid posts an email with an attachment from "my firm's staff" to the KYC's address, sending "no token"
    Then the webhook answers 401
    And nothing is filed

  # H2-2 — Edge case: with enforcement on, a post with a wrong token is refused and nothing is filed
  Scenario: H2-2 A post with a wrong webhook token is refused once enforced
    Given SendGrid inbound enforcement is on
    When SendGrid posts an email with an attachment from "my firm's staff" to the KYC's address, sending "a wrong token"
    Then the webhook answers 401
    And nothing is filed

  # H2-R — Edge case (rollout): with enforcement off, a post without the token is still filed, and logged
  Scenario: H2-R Before enforcement a post without the token is accepted and logged
    Given SendGrid inbound enforcement is off
    When SendGrid posts an email with an attachment from "my firm's staff" to the KYC's address, sending "no token"
    Then the webhook answers 200
    And the email is filed against the KYC with 1 document credited to "my firm's staff"
    And an unauthenticated SendGrid post was logged

  # H2-H — Happy path: with the token, mail to a (legacy, untagged) KYC address is filed and its attachment credited to a sender the firm knows
  Scenario Outline: H2-H A tokened post to a KYC address is filed and credited to <sender>
    Given SendGrid inbound enforcement is on
    When SendGrid posts an email with an attachment from "<sender>" to the KYC's address, sending "the token"
    Then the webhook answers 200
    And the email is filed against the KYC with 1 document credited to "<sender>"

    Examples:
      | sender                 |
      | my firm's staff        |
      | the investor's contact |

  # H2-3 — Edge case: an address naming a class that does not take incoming email is not filed
  Scenario Outline: H2-3 An address naming "<class_name>" is not filed
    Given SendGrid inbound enforcement is on
    When SendGrid posts an email to an address naming the class "<class_name>", sending the token
    Then nothing is filed

    Examples:
      | class_name |
      | user       |
      | file       |

  # H2-6 — Edge case: a sender the owner's firm does not know is not credited with the attachment
  Scenario: H2-6 An attachment from a user of another firm is credited to support, not to the sender
    Given SendGrid inbound enforcement is on
    When SendGrid posts an email with an attachment from "a user of another firm" to the KYC's address, sending "the token"
    Then the webhook answers 200
    And the email is filed against the KYC with 1 document credited to "support"

  # H2-7 — Edge case: while rotating, the previous token is still accepted; the token also works as the Basic auth password
  Scenario Outline: H2-7 A post sending <auth> is accepted
    Given SendGrid inbound enforcement is on
    When SendGrid posts an email with an attachment from "my firm's staff" to the KYC's address, sending "<auth>"
    Then the webhook answers 200
    And the email is filed against the KYC with 1 document credited to "my firm's staff"

    Examples:
      | auth                                 |
      | the previous token                   |
      | the token as the Basic auth password |

  # H2-8 — Happy path: a tokened post to a deal-ingest address goes to the deal ingest pipeline, not to incoming emails
  @deal_update_agent_v2
  Scenario: H2-8 A tokened post to a deal ingest address is routed to deal ingest
    Given SendGrid inbound enforcement is on
    And my firm has a deal "Series B" with an ingest address
    When SendGrid posts an email from my firm's staff to the deal's ingest address, sending the token
    Then the webhook answers 200
    And a v2 AgentIngestedEmail should be created with status "pending"
    And no incoming email is filed

  # H2-8 — Edge case: in production, deal-ingest mail without the email auth headers (no SPF/DKIM verdict) is dropped
  @deal_update_agent_v2
  Scenario: H2-8 In production a deal ingest post without email auth headers is dropped
    Given SendGrid inbound enforcement is on
    And my firm has a deal "Series B" with an ingest address
    And deal ingest requires email auth headers, as in production
    When SendGrid posts an email without headers from my firm's staff to the deal's ingest address, sending the token
    Then the webhook answers 200
    And no v2 AgentIngestedEmail should be created
    And no incoming email is filed
