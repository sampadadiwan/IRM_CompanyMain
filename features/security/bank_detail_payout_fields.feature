@bank_detail_change
Feature: Only the right people mark and unmark payout fields (OWASP review 2026-11 M14 — §8 refusals)
  Marking a custom field as a payout field only tightens the rules, so a company admin (or CapHive support) may do it;
  unmarking or deleting a marked field loosens them, so only CapHive support may. Only text fields on KYC forms can
  be marked. Another firm reaches nothing.
  Worked examples X16–X20:
  openspec/changes/archive/2026-11-10-bank-detail-change-controls/business-rules.md#8-payout-custom-fields-swift--iban--phase-6

  Background:
    Given Horizon Capital's KYC forms have the SWIFT and IBAN custom fields

  # X16 — Error case: Priya (Form Types access, not company admin) sees no "Payout field" control; her payout_field=code
  # is dropped
  Scenario: X16 A non-admin cannot mark
    Given "Priya" may edit Horizon Capital's form types
    When "Priya" opens Form Custom Fields › Edit for "SWIFT Code"
    Then the custom field form has no payout field choice
    When "Priya" sends the payout field "code" for "SWIFT Code" through Form Custom Fields › Edit
    Then "SWIFT Code" on the Individual KYC form is not a payout field

  # X17 — Error case: IBAN marked; Ravi sets IBAN → No in the side panel, and again in Form Types › Edit → both refused
  Scenario: X17 A company admin cannot unmark
    Given "IBAN" is marked as an account identifier on the Individual KYC form
    When "Ravi" saves the custom fields side panel of the KYC "Farah Ali" with:
      | IBAN | No |
    Then the side panel refuses with "Payout fields can only be unmarked by CapHive support."
    When "Ravi" opens the custom fields side panel of the KYC "Farah Ali"
    Then the side panel row "IBAN" is locked with "Payout fields are unmarked by CapHive support"
    When "Ravi" sets the payout field of "IBAN" to "" in Form Types › Edit of the Individual KYC form
    Then the Form Types save is refused with "Payout fields can only be unmarked by CapHive support."
    And "IBAN" on the Individual KYC form is a payout field of kind "account"

  # X18 — Error case: SWIFT marked; Ravi finds no ✕ on SWIFT Code in the side panel (locked chip "Support"); a Form
  # Custom Fields DELETE is refused; the field stays
  Scenario: X18 A company admin cannot delete a marked field
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    When "Ravi" opens the custom fields side panel of the KYC "Farah Ali"
    Then the side panel row "SWIFT Code" has no remove button
    When "Ravi" removes "SWIFT Code" in the custom fields side panel of the KYC "Farah Ali"
    Then the side panel refuses with "Payout fields can only be unmarked by CapHive support."
    When "Ravi" deletes the custom field "SWIFT Code" through Form Custom Fields
    Then "Ravi" is told "Access Denied"
    And "SWIFT Code" on the Individual KYC form is a payout field of kind "code"

  # X19 — Error case: Ravi sends a mark for the check box "Foreign account?", for a text area on the KYC form and for a
  # text field on the Investor form → all refused; nothing saved
  Scenario: X19 Only text fields on KYC forms can be marked
    When "Ravi" sets the payout field of "Foreign account?" to "code" in Form Types › Edit of the Individual KYC form
    Then the Form Types save is refused with "Only text fields on a KYC form can be payout fields"
    When "Ravi" sets the payout field of "Bank Address" to "code" in Form Types › Edit of the Individual KYC form
    Then the Form Types save is refused with "Only text fields on a KYC form can be payout fields"
    When "Ravi" sets the payout field of "Investor SWIFT" to "code" in Form Types › Edit of the Investor form
    Then the Form Types save is refused with "Only text fields on a KYC form can be payout fields"
    And "Foreign account?" on the Individual KYC form is not a payout field
    And "Bank Address" on the Individual KYC form is not a payout field
    And "Investor SWIFT" on the Investor form is not a payout field

  # X20 — Error case: Omar (Northwind) sends the side panel save and a Form Types update for Horizon's KYC form → refused
  Scenario: X20 Another firm marks nothing
    When "Omar" saves the custom fields side panel of Horizon's Individual KYC form with:
      | SWIFT Code | Bank code |
    Then Omar's request is refused
    When "Omar" sets the payout field of "SWIFT Code" to "code" in Form Types › Edit of the Individual KYC form
    Then Omar's request is refused
    And "SWIFT Code" on the Individual KYC form is not a payout field
