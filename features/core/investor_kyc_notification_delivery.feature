@rack_test
Feature: InvestorKyc notification email delivery gate
  Covers NotificationExtensions#email_enabled (config/initializers/noticed.rb) directly.
  BaseNotifier bypasses email_enabled entirely in Rails.env.test? (its deliver_by :email
  only checks custom_notification_body_present? there), so the ActionMailer::Base.deliveries
  assertions used elsewhere in this suite cannot exercise this gate - these scenarios build
  the notification and call email_enabled directly instead.

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=KycNotifDeliveryFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=KycNotifDeliveryInvestor" with "1" users
    And there is a fund "name=KycNotifDeliveryFund1" for the entity "name=KycNotifDeliveryFund"
    And there is a KYC for the investor with submission_status "link_sent"
    And the investor kyc has a capital commitment on the fund

  # ─────────────────────────────────────────────────────────────────────────────
  # 1. The fix: a switched-away, authorized investor advisor still gets the email
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @email_enabled
  Scenario: A switched-away investor advisor with show access still has email delivery enabled
    Given there is an entity "name=KycNotifDeliveryAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=notif_delivery_advisor@example.com" for the entity "name=KycNotifDeliveryAdvisorFirm"
    And the user "notif_delivery_advisor@example.com" has role "investor_advisor"
    And the advisor "notif_delivery_advisor@example.com" is switched into entity "name=KycNotifDeliveryFund"
    And I grant "read" access to the fund for user "notif_delivery_advisor@example.com"
    # Now switch them away - their grant and AccessRight on KycNotifDeliveryFund stand regardless.
    And there is an entity "name=KycNotifDeliveryOtherEntity;entity_type=Investment Fund"
    And the advisor "notif_delivery_advisor@example.com" is switched into entity "name=KycNotifDeliveryOtherEntity"
    When I build a KYC updated notification for "notif_delivery_advisor@example.com"
    Then email_enabled should be true for the notification

  # ─────────────────────────────────────────────────────────────────────────────
  # 2. The additive property: the new branch neither over-grants nor disturbs the
  #    two pre-existing checks
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @email_enabled
  Scenario: The new check is additive - it correctly denies an unauthorized advisor and leaves pre-existing behavior untouched
    Given there is an entity "name=KycNotifDeliveryAdvisorFirm2;entity_type=Investor Advisor"
    And there is a user "email=notif_delivery_no_access@example.com" for the entity "name=KycNotifDeliveryAdvisorFirm2"
    And the user "notif_delivery_no_access@example.com" has role "investor_advisor"
    And the advisor "notif_delivery_no_access@example.com" is switched into entity "name=KycNotifDeliveryFund"
    # No AccessRight granted for this advisor - InvestorKycPolicy#show? must deny them.
    # Switch away too, so the pre-existing model.entity_id == recipient.entity_id branch
    # can't trivially grant this on its own and mask what's actually being tested.
    And there is an entity "name=KycNotifDeliveryOtherEntity3;entity_type=Investment Fund"
    And the advisor "notif_delivery_no_access@example.com" is switched into entity "name=KycNotifDeliveryOtherEntity3"
    When I build a KYC updated notification for "notif_delivery_no_access@example.com"
    Then email_enabled should be false for the notification

    # A plain employee currently in the KYC's entity: granted by the pre-existing
    # model.entity_id == recipient.entity_id rule, unrelated to the new branch.
    Given there is a user "email=notif_delivery_employee@example.com" for the entity "name=KycNotifDeliveryFund"
    And the user "notif_delivery_employee@example.com" has role "employee"
    When I build a KYC updated notification for "notif_delivery_employee@example.com"
    Then email_enabled should be true for the notification

    # An outsider with no investor-advisor role and no relationship to the entity at all.
    Given there is an entity "name=KycNotifDeliveryOtherEntity2;entity_type=Investment Fund"
    And there is a user "email=notif_delivery_outsider@example.com" for the entity "name=KycNotifDeliveryOtherEntity2"
    And the user "notif_delivery_outsider@example.com" has role "employee"
    When I build a KYC updated notification for "notif_delivery_outsider@example.com"
    Then email_enabled should be false for the notification

  # ─────────────────────────────────────────────────────────────────────────────
  # 3. The entity-scoped gate: holding an investor-advisor grant SOMEWHERE does not
  #    leak into an unrelated notifier/entity whose own policy would say yes for an
  #    unrelated reason (DocumentPolicy#show? is unconditionally true for a public
  #    document). This is what distinguishes the fix from a bare role check.
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @email_enabled
  Scenario: Holding an investor-advisor grant elsewhere does not grant email for an unrelated public document
    Given there is an entity "name=KycNotifDeliveryAdvisorFirm3;entity_type=Investor Advisor"
    And there is a user "email=notif_delivery_doc_advisor@example.com" for the entity "name=KycNotifDeliveryAdvisorFirm3"
    And the user "notif_delivery_doc_advisor@example.com" has role "investor_advisor"
    And the advisor "notif_delivery_doc_advisor@example.com" is switched into entity "name=KycNotifDeliveryFund"
    And I grant "read" access to the fund for user "notif_delivery_doc_advisor@example.com"
    # Switch into a second entity, so the advisor now holds grants on two entities -
    # neither of which is the document's own entity below.
    And there is an entity "name=KycNotifDeliveryOtherEntity4;entity_type=Investment Fund"
    And the advisor "notif_delivery_doc_advisor@example.com" is switched into entity "name=KycNotifDeliveryOtherEntity4"
    # A public document on a THIRD entity the advisor holds no grant on at all.
    # DocumentPolicy#show? returns true unconditionally for it (public_visibility), but the
    # entity-scoped gate in investor_advisor_show_enabled must still deny, since Pundit is
    # never even asked unless a grant exists on this specific entity.
    Given there is an entity "name=KycNotifDeliveryDocEntity;entity_type=Investment Fund"
    And there is a user "email=notif_delivery_doc_owner@example.com" for the entity "name=KycNotifDeliveryDocEntity"
    And there is a folder "name=KycNotifDeliveryDocFolder" for the entity "name=KycNotifDeliveryDocEntity"
    And there is a public document in the folder "name=KycNotifDeliveryDocFolder"
    When I build a document notification for "notif_delivery_doc_advisor@example.com"
    Then email_enabled should be false for the notification

  # ─────────────────────────────────────────────────────────────────────────────
  # 4. The flip side of 3, and the limit of this fix's scope: the gate is scoped to
  #    the model's entity, NOT to InvestorKyc. A grant on the document's OWN entity
  #    does reach DocumentPolicy#show?, which is unconditionally true for a public
  #    document - so a switched-away advisor now gets email for that entity's public
  #    documents where before they got none. Pinned here because it is a real
  #    behavior change beyond InvestorKyc notifications (see design.md - Impact).
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @email_enabled
  Scenario: A switched-away advisor does get email for a public document on an entity they hold a grant on
    Given there is an entity "name=KycNotifDeliveryAdvisorFirm4;entity_type=Investor Advisor"
    And there is a user "email=notif_delivery_same_entity@example.com" for the entity "name=KycNotifDeliveryAdvisorFirm4"
    And the user "notif_delivery_same_entity@example.com" has role "investor_advisor"
    And the advisor "notif_delivery_same_entity@example.com" is switched into entity "name=KycNotifDeliveryFund"
    And there is an entity "name=KycNotifDeliveryOtherEntity5;entity_type=Investment Fund"
    And the advisor "notif_delivery_same_entity@example.com" is switched into entity "name=KycNotifDeliveryOtherEntity5"
    # The public document lives on KycNotifDeliveryFund - the entity the advisor holds a grant on
    # but is no longer switched into.
    And there is a folder "name=KycNotifDeliverySameEntityFolder" for the entity "name=KycNotifDeliveryFund"
    And there is a public document in the folder "name=KycNotifDeliverySameEntityFolder"
    When I build a document notification for "notif_delivery_same_entity@example.com"
    Then email_enabled should be true for the notification

  # ─────────────────────────────────────────────────────────────────────────────
  # 5. email_method reaches the notifier as a String once it has crossed a job
  #    boundary, so #url has to compare it as one. A Symbol-only comparison sends
  #    the recipient of a KYC-request email to the read-only page instead of the
  #    form they are being asked to fill in.
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification
  Scenario: A KYC-request notification links to the editable form even when email_method is a string
    Given there is a user "email=kyc_url_recipient@example.com" for the entity "name=KycNotifDeliveryFund"
    When I build a KYC notification for "kyc_url_recipient@example.com" with email_method "notify_kyc_required"
    Then the notification url should be the editable KYC form
    When I build a KYC notification for "kyc_url_recipient@example.com" with email_method "kyc_required_reminder"
    Then the notification url should be the editable KYC form
    # Every other email_method keeps pointing at the read-only record.
    When I build a KYC notification for "kyc_url_recipient@example.com" with email_method "notify_kyc_updated"
    Then the notification url should be the read-only KYC page

  # ─────────────────────────────────────────────────────────────────────────────
  # Errors inside the advisor check fail closed. A policy that raises is reported,
  # because rescuing it quietly would look exactly like an intentional "no".
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @email_enabled
  Scenario: A policy whose show? raises means no email, and the error is reported
    Given there is an entity "name=KycNotifDeliveryRaiseFirm;entity_type=Investor Advisor"
    And there is a user "email=notif_delivery_raise@example.com" for the entity "name=KycNotifDeliveryRaiseFirm"
    And the user "notif_delivery_raise@example.com" has role "investor_advisor"
    And the advisor "notif_delivery_raise@example.com" is switched into entity "name=KycNotifDeliveryFund"
    And there is an entity "name=KycNotifDeliveryRaiseOther;entity_type=Investment Fund"
    And the advisor "notif_delivery_raise@example.com" is switched into entity "name=KycNotifDeliveryRaiseOther"
    And InvestorKycPolicy#show? raises an error
    And error reports are being watched
    When I build a KYC updated notification for "notif_delivery_raise@example.com"
    Then email_enabled should be false for the notification
    And the error should have been reported
    And the error report should let us troubleshoot it for "notif_delivery_raise@example.com"

  @kyc_notification @email_enabled
  Scenario: A model with no policy means no email, and nothing is reported
    Given there is an entity "name=KycNotifDeliveryNoPolicyFirm;entity_type=Investor Advisor"
    And there is a user "email=notif_delivery_no_policy@example.com" for the entity "name=KycNotifDeliveryNoPolicyFirm"
    And the user "notif_delivery_no_policy@example.com" has role "investor_advisor"
    And the advisor "notif_delivery_no_policy@example.com" is switched into entity "name=KycNotifDeliveryFund"
    And there is an entity "name=KycNotifDeliveryNoPolicyOther;entity_type=Investment Fund"
    And the advisor "notif_delivery_no_policy@example.com" is switched into entity "name=KycNotifDeliveryNoPolicyOther"
    And no Pundit policy can be found
    And error reports are being watched
    When I build a KYC updated notification for "notif_delivery_no_policy@example.com"
    Then email_enabled should be false for the notification
    And no error should have been reported
