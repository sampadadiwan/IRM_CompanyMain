Feature: Evergreen fees — performance fee above a class high-water mark, management fee on NAV
  Worked examples H29, H30, E38–E44, E127–E133 (performance fee); H27, H28, E35–E37, E134, E136 (management fee, phase 7)
  — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 60000 | 2025-09-01 |
      | B LLP    | F-031 | A     | 40000 | 2025-09-01 |

  # H29 — Happy path: 20 % above a ₹10,000 mark at ₹10,220 a unit accrues ₹44,00,000 and NAV per unit falls to ₹10,176.
  Scenario: Performance fee accrues above the mark
    Given class "A" has the performance fee "pct=20"
    And the high-water mark of class "A" was set to "10,000" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents         | 44,00,000 |
      | nav_per_unit_before_perf_cents | 10,220    |
      | nav_per_unit_cents             | 10,176    |

  # H30 — Happy path: approving the 31 Dec NAV (annual crystallisation) crystallises ₹44,00,000 across both folios and raises the mark to ₹10,176.
  Scenario: Crystallisation raises the mark
    Given class "A" has the performance fee "pct=20;crystallisation=annual"
    And the high-water mark of class "A" was set to "10,000" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-12-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-12-31"
    And I approve the NAV
    Then the class "A" NAV for "2026-12-31" should be:
      | crystallised    | true   |
      | hwm_after_cents | 10,176 |
    And the crystallised performance fee entries for "2026-12-31" total "44,00,000" across "2" folios

  # E38 — Edge case: NAV per unit ₹10,220 below a ₹10,400 mark accrues no performance fee.
  Scenario: No performance fee below the mark
    Given class "A" has the performance fee "pct=20"
    And the high-water mark of class "A" was set to "10,400" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents | 0      |
      | nav_per_unit_cents     | 10,220 |

  # E39 — Edge case: a hard 8 % hurdle over 91 days charges only above the hurdle-adjusted mark ₹10,199.45 — ₹4,10,958.90.
  Scenario: Hard hurdle charges only above the hurdle-adjusted mark
    Given class "A" has the performance fee "pct=20;hurdle=8;hurdle_type=hard"
    And the high-water mark of class "A" was set to "10,000" on "2026-08-01"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents | 4,10,958.90 |

  # E40 — Edge case: a soft hurdle, once beaten, charges the whole gain over the mark — ₹44,00,000.
  Scenario: Soft hurdle charges the whole gain once beaten
    Given class "A" has the performance fee "pct=20;hurdle=8;hurdle_type=soft"
    And the high-water mark of class "A" was set to "10,000" on "2026-08-01"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents | 44,00,000 |

  # E41 — Edge case: a soft hurdle not beaten (₹10,150 vs ₹10,199.45) charges nothing.
  Scenario: Soft hurdle not beaten charges nothing
    Given class "A" has the performance fee "pct=20;hurdle=8;hurdle_type=soft"
    And the high-water mark of class "A" was set to "10,000" on "2026-08-01"
    And the portfolio fair value is "101,50,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents | 0 |

  # E42 — Edge case: a class with performance fee model None shows no performance fee lines and accrues nothing.
  Scenario: Performance fee model None shows no performance fee lines
    Given class "A" has no performance fee
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "A" NAV for "2026-10-31"
    Then I should not see "Accrued performance fee"
    And the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents | 0 |

  # E43 — Edge case: approving a 30 Nov NAV under annual crystallisation crystallises nothing.
  Scenario: No crystallisation off-schedule
    Given class "A" has the performance fee "pct=20;crystallisation=annual"
    And the high-water mark of class "A" was set to "10,000" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-11-30"
    And the approver logs in
    And I open the class "A" NAV for "2026-11-30"
    And I approve the NAV
    Then the class "A" NAV for "2026-11-30" should be:
      | crystallised | false |
    And the crystallised performance fee entries for "2026-11-30" total "0" across "0" folios

  # E44 — Edge case: reopening a crystallised NAV deletes its crystallisation entries and restores the ₹10,000 mark.
  Scenario: Reopening reverses crystallisation
    Given class "A" has the performance fee "pct=20;crystallisation=annual"
    And the high-water mark of class "A" was set to "10,000" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-12-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-12-31"
    And I approve the NAV
    And I reopen the NAV
    Then the class "A" NAV for "2026-12-31" should be:
      | crystallised | false |
    And the crystallised performance fee entries for "2026-12-31" total "0" across "0" folios
    And the high-water mark of class "A" before "2027-03-31" is "10,000"

  # H27 — Happy path: the fee formula accrues ₹12,60,000 for November on NAV and the 30 Nov draft picks it up as payable.
  Scenario: Management fee accrues on NAV and feeds the next NAV
    Given class "A" charges a management fee of "1.5"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And the management fee formula is added
    And the Allocation Run "start_date=2026-11-01;end_date=2026-11-30" is created for the "Alpha Long-Short Fund"
    Then the management fee entries for "2026-11-30" should total "12,60,000"
    Given the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-11-30"
    Then the class "A" NAV for "2026-11-30" should be:
      | mgmt_fee_payable_cents | 12,60,000 |

  # H28 — Happy path: payable rolls up month by month and a "Management Fee Paid" entry on 5 Jan clears it, leaving only January's accrual.
  @rack_test
  Scenario: The fee is paid on its own schedule
    Given class "A" charges a management fee of "1.5"
    And the high-water mark of class "A" was set to "9,000" on "2026-09-30"
    And the portfolio fair value is "98,26,00,000"
    And folio "F-012" accrued a management fee of "12,51,805" on "2026-10-31"
    When the class "A" NAV for "2026-10-31" is drafted and approved
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 12,51,805 |
    Given folio "F-012" accrued a management fee of "12,60,000" on "2026-11-30"
    When the class "A" NAV for "2026-11-30" is drafted and approved
    Then the class "A" NAV for "2026-11-30" should be:
      | mgmt_fee_payable_cents | 25,11,805 |
    Given folio "F-012" accrued a management fee of "12,93,082" on "2026-12-31"
    When the class "A" NAV for "2026-12-31" is drafted and approved
    Then the class "A" NAV for "2026-12-31" should be:
      | mgmt_fee_payable_cents | 38,04,887 |
    Given the fund ledger has "Management Fee Paid" of "38,04,887" on "2027-01-05"
    And folio "F-012" accrued a management fee of "13,12,192" on "2027-01-31"
    When the class "A" NAV for "2027-01-31" is drafted and approved
    Then the class "A" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | 13,12,192 |

  # E35 — Edge case: a NAV drafted past the last management-fee accrual shows the "accrued only to" warning.
  Scenario: A missing accrual is flagged on the NAV
    Given class "A" charges a management fee of "1.5"
    And folio "F-012" accrued a management fee of "12,51,805" on "2026-10-31"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-11-30"
    And I open the class "A" NAV for "2026-11-30"
    Then I should see "Management fee accrued only to 31 October 2026 — run the fee formula to 30 November 2026, then recalculate"

  # E36 — Edge case: a class charging 0 % management fee shows no accrual warning.
  Scenario: A class without a management fee shows no accrual warning
    Given class "A" charges a management fee of "0"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-11-30"
    And I open the class "A" NAV for "2026-11-30"
    Then I should not see "Management fee accrued only to"

  # E37 — Edge case: a quarterly run accrues the fee for all 92 days — ₹38,64,000.
  @rack_test
  Scenario: A quarterly NAV accrues the fee for the whole quarter
    Given class "A" charges a management fee of "1.5"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,220" and units "100000"
    And the management fee formula is added
    And the Allocation Run "start_date=2026-10-01;end_date=2026-12-31" is created for the "Alpha Long-Short Fund"
    Then the management fee entries for "2026-12-31" should total "38,64,000"

  # ---- Edge cases (E127–E134, E136) ----

  # E127 — Edge case: NAV per unit exactly at the mark (₹10,220 = ₹10,220) is not above it, so no performance fee accrues.
  Scenario: No performance fee exactly at the mark
    Given class "A" has the performance fee "pct=20"
    And the high-water mark of class "A" was set to "10,220" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | hwm_cents              | 10,220 |
      | perf_fee_accrued_cents | 0      |
      | nav_per_unit_cents     | 10,220 |

  # E128 — Edge case: when the quarter ends on a Saturday (30 Sep 2028), the NAV dated on its last business day, Friday 29 Sep, crystallises.
  @rack_test
  Scenario: Crystallisation on the last business day before a weekend quarter-end
    Given class "A" has the performance fee "pct=20;crystallisation=quarterly"
    And the high-water mark of class "A" was set to "10,000" on "2028-06-30"
    And the portfolio fair value is "102,20,00,000"
    When the class "A" NAV for "2028-09-29" is drafted and approved
    Then the class "A" NAV for "2028-09-29" should be:
      | perf_fee_accrued_cents | 44,00,000 |
      | crystallised           | true      |
      | hwm_after_cents        | 10,176    |
    And the crystallised performance fee entries for "2028-09-29" total "44,00,000" across "2" folios

  # E129 — Edge case: after a loss month (₹9,800) the mark stays at the crystallised ₹10,176, and on recovery to ₹10,300 only the gain above it is charged — 20 % × ₹124 × 1,00,000 = ₹24,80,000.
  @rack_test
  Scenario: The mark holds through a loss and charges only the recovery above it
    Given class "A" has the performance fee "pct=20"
    And the high-water mark of class "A" was set to "10,176" on "2026-12-31"
    And the portfolio fair value is "98,00,00,000"
    When the class "A" NAV for "2027-01-31" is drafted and approved
    Then the class "A" NAV for "2027-01-31" should be:
      | hwm_cents              | 10,176 |
      | perf_fee_accrued_cents | 0      |
      | nav_per_unit_cents     | 9,800  |
    Given the portfolio fair value is "103,00,00,000"
    When the class "A" NAV for "2027-02-28" is drafted and approved
    Then the class "A" NAV for "2027-02-28" should be:
      | hwm_cents                      | 10,176        |
      | perf_fee_accrued_cents         | 24,80,000     |
      | nav_per_unit_before_perf_cents | 10,300        |
      | nav_per_unit_cents             | 10,275.20     |
      | nav_cents                      | 102,75,20,000 |

  # E130 — Edge case: on a crystallisation date with nothing accrued (₹10,220 below a ₹10,400 mark) nothing crystallises and the mark stays ₹10,400.
  @rack_test
  Scenario: A crystallisation date with no fee crystallises nothing
    Given class "A" has the performance fee "pct=20;crystallisation=annual"
    And the high-water mark of class "A" was set to "10,400" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    When the class "A" NAV for "2026-12-31" is drafted and approved
    Then the class "A" NAV for "2026-12-31" should be:
      | perf_fee_accrued_cents | 0     |
      | crystallised           | false |
    And the crystallised performance fee entries for "2026-12-31" total "0" across "0" folios
    And the high-water mark of class "A" before "2027-03-31" is "10,400"

  # E131 — Edge case: with no crystallisation yet, the class's first approved NAV per unit (₹10,000 on 30 Sep) is the mark, so ₹10,220 accrues ₹44,00,000.
  Scenario: The first approved NAV sets the first mark
    Given class "A" has the performance fee "pct=20"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "100000"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | hwm_cents              | 10,000    |
      | perf_fee_accrued_cents | 44,00,000 |
      | nav_per_unit_cents     | 10,176    |

  # E132 — Edge case: a class's very first NAV has no mark yet, so no performance fee accrues and NAV per unit is the full ₹10,220.
  Scenario: The very first NAV of a class accrues no performance fee
    Given class "A" has the performance fee "pct=20"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | perf_fee_accrued_cents | 0      |
      | nav_per_unit_cents     | 10,220 |
    And the class "A" NAV for "2026-10-31" should have no high-water mark

  # E133 — Edge case: reopening a crystallised NAV and approving it again crystallises once — ₹44,00,000 across 2 folios, not twice.
  Scenario: Re-approving a reopened crystallising NAV crystallises once
    Given class "A" has the performance fee "pct=20;crystallisation=annual"
    And the high-water mark of class "A" was set to "10,000" on "2025-12-31"
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-12-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-12-31"
    And I approve the NAV
    And I reopen the NAV
    And I approve the NAV
    Then the class "A" NAV for "2026-12-31" should be:
      | status          | approved |
      | crystallised    | true     |
      | hwm_after_cents | 10,176   |
    And the crystallised performance fee entries for "2026-12-31" total "44,00,000" across "2" folios

  # E134 — Edge case: February of a leap year accrues 29 days on a 365-day year — ₹102,20,00,000 × 1.5 % × 29 ÷ 365 = ₹12,18,000.
  @rack_test
  Scenario: A leap-year February accrues 29 days
    Given class "A" charges a management fee of "1.5"
    And an approved NAV for class "A" on "2028-01-31" with NAV per unit "10,220" and units "100000"
    And the management fee formula is added
    And the Allocation Run "start_date=2028-02-01;end_date=2028-02-29" is created for the "Alpha Long-Short Fund"
    Then the management fee entries for "2028-02-29" should total "12,18,000"

  # E136 — Edge case: when the latest accrual is dated on the NAV date itself the fee is up to date — no warning, and the ₹12,60,000 is payable.
  Scenario: An accrual dated on the NAV date shows no warning
    Given class "A" charges a management fee of "1.5"
    And folio "F-012" accrued a management fee of "12,60,000" on "2026-11-30"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-11-30"
    And I open the class "A" NAV for "2026-11-30"
    Then I should not see "Management fee accrued only to"
    And the class "A" NAV for "2026-11-30" should be:
      | mgmt_fee_payable_cents | 12,60,000 |

  # ---- Fees tab: the payable's working and what to do per NAV (fees screen redesign, 11 Oct 2026) ----

  # H104 — Happy path: the Fees tab shows how the 30 Nov payable was reached — ₹12,51,805 owed at 31 Oct + ₹12,60,000 accrued − ₹12,51,805 paid on 5 Nov = ₹12,60,000.
  @rack_test
  Scenario: The fees tab shows the working of each payable
    Given class "A" charges a management fee of "1.5"
    And the portfolio fair value is "98,26,00,000"
    And folio "F-012" accrued a management fee of "12,51,805" on "2026-10-31"
    And the class "A" NAV for "2026-10-31" is drafted and approved
    And the fund ledger has "Management Fee Paid" of "12,51,805" on "2026-11-05"
    And folio "F-012" accrued a management fee of "12,60,000" on "2026-11-30"
    And the class "A" NAV for "2026-11-30" is drafted and approved
    When I open the fees tab
    Then the fees row for class "A" on "2026-11-30" should show "12,51,805.00", "12,60,000.00", "12,51,805.00" and "12,60,000.00"
    And the fees row for class "A" on "2026-11-30" should show "Accrued to"

  # E318 — Edge case: a NAV approved with no management fee accrued shows "No fee in this NAV" and, with no dealing date priced at it, a Reopen button for an approver.
  @rack_test
  Scenario: A NAV approved without its fee offers Reopen
    Given the user has role "approver"
    And class "A" charges a management fee of "1.5"
    And the portfolio fair value is "98,26,00,000"
    And the class "A" NAV for "2026-10-31" was drafted and approved before a fee was required
    When I open the fees tab
    Then the fees row for class "A" on "2026-10-31" should show "No fee in this NAV"
    And the fees row for class "A" on "2026-10-31" should offer Reopen

  # E319 — Edge case: the same NAV, once a dealing date was priced at it, is locked — the row names the dealing date and offers no Reopen.
  @rack_test
  Scenario: A NAV without its fee that priced a dealing date is locked
    Given the user has role "approver"
    And class "A" charges a management fee of "1.5"
    And the portfolio fair value is "98,26,00,000"
    And the class "A" NAV for "2026-10-31" was drafted and approved before a fee was required
    And the class "A" NAV for "2026-10-31" priced a dealing date on "2026-11-02"
    When I open the fees tab
    Then the fees row for class "A" on "2026-10-31" should show "Locked: the"
    And the fees row for class "A" on "2026-10-31" should not offer Reopen

  # E320 — Edge case: a NAV approved with the fee accrued only to 31 Oct shows "Accrued only to" on its 30 Nov row.
  @rack_test
  Scenario: A NAV with the fee accrued only partway is flagged
    Given class "A" charges a management fee of "1.5"
    And the portfolio fair value is "98,26,00,000"
    And folio "F-012" accrued a management fee of "12,51,805" on "2026-10-31"
    And the class "A" NAV for "2026-11-30" was drafted and approved before a fee was required
    When I open the fees tab
    Then the fees row for class "A" on "2026-11-30" should show "Accrued only to"

  # E321 — Edge case: a class whose NAVs are all uploaded has no payable working to show — the columns are left out, the row says the administrator's figure includes the fee, and step 1 says so too.
  @rack_test
  Scenario: Uploaded NAVs show the fee as included by the administrator
    Given class "A" charges a management fee of "1.5"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    When I open the fees tab
    Then I should see "Fee included by the administrator"
    And I should see "Fee accrues — in the administrator's NAV"
    And I should not see "Payable at previous NAV"

  # E325 — Edge case: a class's first NAV, with no units outstanding yet, has nothing to charge a fee on — the Fees tab says "No units yet", not "No fee in this NAV", and the NAV page shows no accrual warning (F8).
  @rack_test
  Scenario: A NAV with no units outstanding is not flagged for a missing fee
    Given class "A" charges a management fee of "1.5"
    And a computed approved NAV for class "A" on "2025-08-29" with no units outstanding
    When I open the fees tab
    Then the fees row for class "A" on "2025-08-29" should show "No units yet"
    When I open the class "A" NAV for "2025-08-29"
    Then I should not see "No management fee accrued yet"
