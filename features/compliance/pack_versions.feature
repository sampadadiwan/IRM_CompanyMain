Feature: Pack versions and locking
  Locked CapHive packs; each version applies to all funds, new funds only, or all with a transition period.
  Worked examples: openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md (group 10)

  Background:
    Given the Horizon compliance setup
    And SEBI funds "Fund N1" started "2027-01-01", "Fund N0" started "2026-12-31" and "Fund U" with no start date

  # H46 — Happy path: applicability A moves every fund on 01 Jan 2027
  Scenario: H46 A moves every fund
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the nightly compliance runs happen on "2027-01-01" for "Horizon Growth Fund I, Fund N0, Fund N1"
    Then "Horizon Growth Fund I, Fund N0, Fund N1" are on SEBI "v2"

  # H47 — Happy path: applicability B — a fund starting on the applicability date moves
  Scenario: H47 B start on applicability date
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "new_funds" funds
    When the nightly compliance runs happen on "2027-01-01" for "Fund N1"
    Then "Fund N1" are on SEBI "v2"

  # H48 — Happy path: published ahead — the preview shows the effect, nothing is logged
  Scenario: H48 Published ahead, preview
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    And the compliance date is "2026-12-10"
    When "Meera" previews SEBI v2 on "Horizon Growth Fund I"
    Then the preview shows "Single-investee concentration" as "breach"
    And nothing was logged by the preview

  # H49 — Happy path: owners are told when the version is published
  Scenario: H49 Notice on publish
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    Then "Meera" got the compliance notice "SEBI — AIF v2 published — takes effect on"

  # H50 — Happy path: early adoption approved 10 Dec — Growth I on v2 from 11 Dec, others on v1 until 01 Jan
  Scenario: H50 Early adoption
    Given SEBI v2 allowing early adoption is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When "Meera" requests early adoption of SEBI v2 for "Horizon Growth Fund I" on "2026-12-10"
    And "Rahul" approves the latest request
    And the nightly compliance runs happen on "2026-12-11" for "Horizon Growth Fund I, Fund N0"
    Then "Horizon Growth Fund I" are on SEBI "v2"
    And "Fund N0" are on SEBI "v1"

  # H51 — Happy path: an entity pack version applies from publish (FA v2 published 10 Nov → 11 Nov run)
  Scenario: H51 Entity version from publish
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And the fund agreement v2 is published on "2026-11-10"
    When the nightly compliance run happens on "2026-11-11"
    Then the "Single-sector limit" check on "Horizon Growth Fund I" is "pass"
    And the result records version "v2"

  # H52 — Happy path: on a locked pack, inputs and reference lists are still editable
  Scenario: H52 Locked pack: inputs editable
    When "Meera" maps the sponsor/manager input to "Sponsor" and saves the IC members "A. Rao, K. Shah, M. Iyer" with quorum 2
    Then the setup saves

  # H53 — Happy path: a stricter override on a locked pack is approved — 20% (pack: 25%)
  Scenario: H53 Stricter override on locked pack
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And "Rahul" approves the latest request
    And the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "20% (pack: 25%)"

  # E80 — Edge case: applicability B — a fund starting the day before stays on v1, grandfathered
  Scenario: E80 B start one day before
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "new_funds" funds
    When the nightly compliance runs happen on "2027-01-01" for "Fund N0"
    Then "Fund N0" are on SEBI "v1"

  # E81 — Edge case: a grandfathered fund keeps v1's duties; v2-only duties are not created
  Scenario: E81 Grandfathered keeps v1 duties
    Given SEBI v2 replacing the yearly duty with "New v2 duty" is published on "2026-12-01" effective "2027-01-01" for "new_funds" funds
    When the nightly compliance run happens on "2027-01-02"
    Then "Horizon Growth Fund I" has a "Annual compliance test report / PPM audit" duty
    And "Horizon Growth Fund I" has no "New v2 duty" duty

  # E82 — Edge case: applicability C — on the last transition day a failing new check is a Warning with no item
  Scenario: E82 C last transition day
    Given SEBI v2 with a new failing check is published on "2026-12-01" effective "2027-01-01" with a transition until "2027-06-30"
    When the nightly compliance run happens on "2027-06-30"
    Then the "New v2 investor cap" check on "Horizon Growth Fund I" is "warning"
    And the working shows "In transition until"
    And "Horizon Growth Fund I" has no register item for "New v2 investor cap"

  # E83 — Edge case: applicability C — the day after the transition it is a Breach and an item opens
  Scenario: E83 C day after transition
    Given SEBI v2 with a new failing check is published on "2026-12-01" effective "2027-01-01" with a transition until "2027-06-30"
    When the nightly compliance run happens on "2027-07-01"
    Then the "New v2 investor cap" check on "Horizon Growth Fund I" is "breach"
    And "Horizon Growth Fund I" has 1 register item for "New v2 investor cap" opened on "2027-07-01"

  # E84 — Edge case: applicability C — a fund started on the effective date gets no transition
  Scenario: E84 C started on effective date
    Given SEBI v2 with a new failing check is published on "2026-12-01" effective "2027-01-01" with a transition until "2027-06-30"
    When the nightly compliance run happens on "2027-01-02" for "Fund N1"
    Then the "New v2 investor cap" check on "Fund N1" is "breach"

  # E85 — Edge case: applicability C — a fund started the day before the effective date is in transition
  Scenario: E85 C started day before effective
    Given SEBI v2 with a new failing check is published on "2026-12-01" effective "2027-01-01" with a transition until "2027-06-30"
    When the nightly compliance run happens on "2027-01-02" for "Fund N0"
    Then the "New v2 investor cap" check on "Fund N0" is "warning"

  # E86 — Edge case: applicability B — a fund with no start date: every SEBI check "Could not check — missing: fund start date"
  Scenario: E86 No start date
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "new_funds" funds
    When the nightly compliance run happens on "2027-01-01" for "Fund U"
    Then every SEBI check of "Fund U" says "Could not check — missing: fund start date"

  # E87 — Edge case: owners are reminded exactly 7 days before (25 Dec), not on 24 or 26 Dec
  Scenario: E87 7-day notice boundary
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the morning version reminders run on "2026-12-24", "2026-12-25" and "2026-12-26"
    Then "Meera" got the compliance notice "SEBI — AIF v2 takes effect on" exactly once

  # E88 — Edge case: a grandfathered fund's preview says the version will not apply
  Scenario: E88 Grandfathered preview
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "new_funds" funds
    When "Meera" previews SEBI v2 on "Horizon Growth Fund I"
    Then the compliance preview says "This version will not apply to this fund"

  # E89 — Edge case: pressing preview twice gives the same preview and logs nothing
  Scenario: E89 Preview twice
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When "Meera" previews SEBI v2 on "Horizon Growth Fund I"
    And "Meera" previews SEBI v2 on "Horizon Growth Fund I"
    Then the preview shows "Single-investee concentration" as "breach"
    And nothing was logged by the preview

  # E90 — Edge case: an override of 20% is kept when v2's limit is 22%
  Scenario: E90 Override kept — stricter
    Given an approved override of "Single-investee concentration" on "Horizon Growth Fund I" at 20
    And SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds with the concentration limit at 22
    When the nightly compliance run happens on "2027-01-01"
    Then the override is "approved"
    And the working shows "20% (pack: 22%)"

  # E91 — Edge case: an override of 20% is kept when v2's limit is 20%
  Scenario: E91 Override kept — equal
    Given an approved override of "Single-investee concentration" on "Horizon Growth Fund I" at 20
    And SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds with the concentration limit at 20
    When the nightly compliance run happens on "2027-01-01"
    Then the override is "approved"

  # E92 — Edge case: an override of 20% is dropped when v2's limit is 18%; the result uses 18%
  Scenario: E92 Override dropped
    Given an approved override of "Single-investee concentration" on "Horizon Growth Fund I" at 20
    And SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds with the concentration limit at 18
    When the nightly compliance run happens on "2027-01-01"
    Then the override is "dropped"
    And the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "26.67% > 18%"
    And the working does not show "pack:"

  # E93 — Edge case: an override on a check v2 removes is archived
  Scenario: E93 Override archived
    Given an approved override of "Single-investee concentration" on "Horizon Growth Fund I" at 20
    And SEBI v2 without the concentration check is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens on "2027-01-01"
    Then the override is "archived"

  # E94 — Edge case: an open item on a check v2 removes closes "Check removed"
  Scenario: E94 Removed check closes item
    When the nightly compliance run happens on "2026-11-05"
    Given SEBI v2 without the concentration check is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens on "2027-01-01"
    Then the "sebi_concentration_cat12" item on "Horizon Growth Fund I" is closed as "Check removed"

  # E95 — Edge case: v2 raises the limit to 30% — 26.67% ≤ 30% clears the item
  Scenario: E95 Changed check now passes
    When the nightly compliance run happens on "2026-11-05"
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds with the concentration limit at 30
    When the nightly compliance run happens on "2027-01-01"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is closed as "Cleared by data"

  # E96 — Edge case: v2's limit 26% — 26.67% still fails, the same item stays open
  Scenario: E96 Changed check still fails
    When the nightly compliance run happens on "2026-11-05"
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds with the concentration limit at 26
    When the nightly compliance run happens on "2027-01-01"
    Then "Horizon Growth Fund I" has 1 register item for "Single-investee concentration" opened on "2026-11-05"

  # E97 — Edge case: an entity version published 10 Nov applying 01 Dec — 30 Nov v1, 01 Dec v2
  Scenario: E97 Entity version from a set date
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And the fund agreement v2 is published on "2026-11-10" applying from "2026-12-01"
    When the nightly compliance run happens on "2026-11-30"
    Then the "Single-sector limit" check on "Horizon Growth Fund I" is "pass"
    And the result records version "v1"
    When the nightly compliance run happens on "2026-12-01"
    Then the "Single-sector limit" check on "Horizon Growth Fund I" is "pass"
    And the result records version "v2"

  # E98 — Edge case: an entity pack offers no grandfathering, transition or early adoption
  Scenario: E98 Entity pack: no B/C
    When "Meera" publishes the fund agreement v2 for "new_funds" funds
    Then the entity publish is refused with "Entity packs apply to all funds"

  # E99 — Edge case: SEBI retired 01 Mar 2027 — checked on 28 Feb, not on 01 Mar; history kept
  Scenario: E99 Retirement date
    Given the SEBI pack is retired on "2027-03-01"
    When the nightly compliance run happens on "2027-02-28"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    When the nightly compliance run happens on "2027-03-01"
    Then "Horizon Growth Fund I" has no SEBI results on "2027-03-01"
    And "Horizon Growth Fund I" has SEBI results on "2027-02-28"

  # E100 — Edge case: an early adopter on the effective date stays on v2 with no second switch
  Scenario: E100 Early adopter on effective date
    Given SEBI v2 allowing early adoption is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When "Meera" requests early adoption of SEBI v2 for "Horizon Growth Fund I" on "2026-12-10"
    And "Rahul" approves the latest request
    And the nightly compliance run happens on "2027-01-01"
    Then "Horizon Growth Fund I" are on SEBI "v2"
    And no version switch was recorded for "Horizon Growth Fund I" on "2027-01-01"

  # E101 — Edge case: "Investors in scheme" is not overridable — no override offered
  Scenario: E101 Not-overridable check
    Then the SEBI check "Investors in scheme" is not overridable

  # E102 — Edge case: a SEBI check is locked — Meera has no edit controls
  Scenario: E102 Locked check read-only
    Then "Meera" cannot edit the SEBI pack

  # X50 — Error case: publishing without choosing who it applies to is refused
  Scenario: X50 No applicability
    When Priya publishes a SEBI draft with no applicability
    Then the version publish is refused with "Choose who this version applies to"

  # X51 — Error case: transition ending on the effective date is refused
  Scenario: X51 Transition end = effective
    When Priya publishes a SEBI draft effective "2027-01-01" with a transition until "2027-01-01"
    Then the version publish is refused with "Transition must end after the effective date"

  # X52 — Error case: a looser 30% override on a locked pack is refused
  Scenario: X52 Looser override
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 30 because "Board policy 2026-07"
    Then the compliance request is refused with "Locked pack: overrides can only tighten this limit"

  # X53 — Error case: an override equal to the pack's 25% is refused
  Scenario: X53 Equal override
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 25 because "Board policy 2026-07"
    Then the compliance request is refused with "Same as the pack's limit"

  # X56 — Error case: early adoption of a version that disallows it is refused
  Scenario: X56 Early adoption not allowed
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When "Meera" requests early adoption of SEBI v2 for "Horizon Growth Fund I" on "2026-12-10"
    Then the compliance request is refused with "This version does not allow early adoption"

  # X58 — Error case: undoing an early adoption (back to v1) is refused
  Scenario: X58 Undo early adoption
    Given SEBI v2 allowing early adoption is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When "Meera" requests early adoption of SEBI v2 for "Horizon Growth Fund I" on "2026-12-10"
    And "Rahul" approves the latest request
    And "Meera" requests to move "Horizon Growth Fund I" back to SEBI v1
    Then the compliance request is refused with "Versions cannot be moved backwards"

  # X59 — Error case: pinning a fund to v1 after v2 is effective is refused
  Scenario: X59 Pin to v1
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens on "2027-01-01"
    And "Meera" requests to move "Horizon Growth Fund I" back to SEBI v1
    Then the compliance request is refused with "Versions cannot be moved backwards"
