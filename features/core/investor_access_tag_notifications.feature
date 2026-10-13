@notification @rack_test
Feature: InvestorAccess tag_list — subscription-based notification filtering
  Investor contacts can be tagged with notification topics (e.g. "CapitalCall", "KYC").
  A contact with no tags receives all notifications.
  A contact with tags receives only notifications whose topic intersects their tags.
  Employee notification paths are entirely separate and unaffected.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"

  # ─────────────────────────────────────────────────────────────────────────
  # 1. Core truth table — Approval domain
  #    Proves all four cells: no tag, matching tag, non-matching tag, multi-tag
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Approval notification filtered by investor contact tag_list
    Given the user has role "approver"
    And there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    And there is an approval "title=Tag Filter Test" for the entity
    And the investors are added to the approval
    And the approval responses are generated with status "Pending"
    When the approval is approved internally
    Then the investor contact "<outcome>" the "approval" notification

    Examples:
      | contact_tag  | outcome  | notes                                       |
      |              | receives | No tag — subscribed to all                  |
      | Approval     | receives | Tag matches — subscribed                    |
      | KYC          | skips    | Tag present, no match — excluded            |
      | Approval,KYC | receives | Multiple tags, Approval intersects          |

  # ─────────────────────────────────────────────────────────────────────────
  # 2. Mixed contact list
  #    Proves untagged and matching both receive; non-matching is excluded
  # ─────────────────────────────────────────────────────────────────────────

  Scenario: Mixed tags — untagged and matching contacts receive, non-matching is excluded
    Given the user has role "approver"
    And there is an existing investor "name=Untagged Firm" with "1" users
    And there is an existing investor "name=Approval Firm" with "1" users and investor_access_tags "Approval"
    And there is an existing investor "name=KYC Firm" with "1" users and investor_access_tags "KYC"
    And there is an approval "title=Mixed Tag Test" for the entity
    And the investors are added to the approval
    And the approval responses are generated with status "Pending"
    When the approval is approved internally
    Then the "Untagged Firm" investor contact receives the "approval" notification
    And the "Approval Firm" investor contact receives the "approval" notification
    And the "KYC Firm" investor contact does not receive the "approval" notification

  # ─────────────────────────────────────────────────────────────────────────
  # 3. Employee path is unchanged
  #    Employee receives KYC notification even when investor contact has wrong tag.
  #    Proves the two paths are independent.
  # ─────────────────────────────────────────────────────────────────────────

  Scenario: Employee receives KYC notification regardless of investor contact tags
    Given there is an existing investor "" with "1" users and investor_access_tags "CapitalCall"
    When a KYC is created for the investor with "send_kyc_form_to_user=false"
    Then the employee receives the "KYC updated" employee notification
    And the investor contact does not receive the "KYC" investor notification

  # ─────────────────────────────────────────────────────────────────────────
  # 4. KYC domain
  #    Proves the tag mechanism works for a second notifier type
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: KYC investor notification filtered by contact tag_list
    Given there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    When a KYC is created for the investor with "send_kyc_form_to_user=true"
    Then the investor contact "<outcome>" the "KYC" investor notification

    Examples:
      | contact_tag | outcome  |
      |             | receives |
      | KYC         | receives |
      | Approval    | skips    |

  # ─────────────────────────────────────────────────────────────────────────
  # 5. Capital call domain
  #    Proves the tag mechanism works for fund-based notifications
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Capital call notification filtered by contact tag_list
    Given there is a fund "name=Tag Test Fund" for the entity
    And there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the investors have approved investor access
    When a capital call is created with "percentage_called=20;call_basis=Percentage of Commitment"
    And the capital call is approved
    Then the investor contact "<outcome>" the "CapitalCall" notification

    Examples:
      | contact_tag | outcome  |
      |             | receives |
      | CapitalCall | receives |
      | KYC         | skips    |

  # ─────────────────────────────────────────────────────────────────────────
  # 6. Investor advisor follows same subscription semantics
  #    IAs are stored in investor_accesses, so tags apply equally
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Investor advisor notification filtered by tag_list
    Given the user has role "approver"
    And there is an existing investor "" with "1" users
    And there is an investor advisor with tag_list "<ia_tag>" for the investor
    And there is an approval "title=IA Tag Test" for the entity
    And the investors are added to the approval
    And the approval responses are generated with status "Pending"
    When the approval is approved internally
    Then the investor advisor "<outcome>" the "approval" notification

    Examples:
      | ia_tag   | outcome  |
      | Approval | receives |
      | KYC      | skips    |

  # ─────────────────────────────────────────────────────────────────────────
  # 7. Distribution domain
  #    Proves tag filtering works for CapitalDistributionPaymentNotifier
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Distribution payment notification filtered by contact tag_list
    Given there is a fund "name=Tag Dist Fund" for the entity
    And there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the investors have approved investor access
    And there is an approved capital distribution for the fund
    When the distribution payment notification is sent
    Then the investor contact "<outcome>" the "Distribution" notification

    Examples:
      | contact_tag  | outcome  |
      |              | receives |
      | Distribution | receives |
      | KYC          | skips    |

  # ─────────────────────────────────────────────────────────────────────────
  # 8. Capital Remittance domain
  #    Proves tag filtering works for CapitalRemittanceNotifier#send_notification,
  #    a separate code path from the call-level Notify job (scenario 5)
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Capital remittance notification filtered by contact tag_list
    Given there is a fund "name=Tag CR Fund" for the entity
    And there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the investors have approved investor access
    When a capital call is created with "percentage_called=20;call_basis=Percentage of Commitment"
    And the capital call is approved
    And the capital remittance notification is sent
    Then the investor contact "<outcome>" the "CapitalRemittance" notification

    Examples:
      | contact_tag | outcome  |
      |             | receives |
      | CapitalCall | receives |
      | KYC         | skips    |

  # ─────────────────────────────────────────────────────────────────────────
  # 9. Investment Opportunity domain
  #    Proves tag filtering works for InvestmentOpportunityNotifier
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Investment opportunity notification filtered by contact tag_list
    Given there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    And there is an investment_opportunity ""
    And the investors are added to the investment_opportunity
    When the investment opportunity open notification is sent
    Then the investor contact "<outcome>" the "InvestmentOpportunity" notification

    Examples:
      | contact_tag           | outcome  |
      |                       | receives |
      | InvestmentOpportunity | receives |
      | KYC                   | skips    |

  # ─────────────────────────────────────────────────────────────────────────
  # 10. Secondary Sale / Interest domain
  #     Proves tag filtering works for InterestNotifier via Interest#notify_interest
  # ─────────────────────────────────────────────────────────────────────────

  Scenario Outline: Interest notification filtered by contact tag_list
    Given there is an existing investor "" with "1" users and investor_access_tags "<contact_tag>"
    And there is a secondary sale for the entity
    And there is an interest from the investor in the secondary sale
    When the interest notification is sent
    Then the investor contact "<outcome>" the "SecondarySale" notification

    Examples:
      | contact_tag   | outcome  |
      |               | receives |
      | SecondarySale | receives |
      | KYC           | skips    |

  Scenario: Interest notification placeholder substitution
    Given there is an existing investor "" with "1" users
    And there is a secondary sale for the entity
    And there is an interest from the investor in the secondary sale
    Given there is a custom notification with placeholders for the interest with subject "Interest Placeholder Test"
    When the interest notification is sent with placeholders
    Then the interest notification placeholders are resolved correctly

  Scenario: Secondary sale notification placeholder substitution
    Given there is an existing investor "" with "1" users
    And there is a secondary sale for the entity
    And there is an interest from the investor in the secondary sale
    Given there is a custom notification with placeholders for the secondary sale with subject "SecondarySale Placeholder Test"
    When the secondary sale notification is sent with placeholders
    Then the secondary sale notification placeholders are resolved correctly

  Scenario: Offer notification placeholder substitution
    Given there is an existing investor "" with "1" users
    And there is a secondary sale for the entity
    And there is an interest from the investor in the secondary sale
    And there is an offer for the investor in the secondary sale
    Given there is a custom notification with placeholders for the offer with subject "Offer Placeholder Test"
    When the offer notification is sent with placeholders
    Then the offer notification placeholders are resolved correctly
