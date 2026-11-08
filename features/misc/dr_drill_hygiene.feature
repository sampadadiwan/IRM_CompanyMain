@rack_test
Feature: A DR drill refuses to collide, never pages anyone, and only stops its own servers
  A drill rehearses a real recovery, so it must be repeatable, quiet and safe. It checks the
  Pulumi stack lock before starting and refuses - without logging a fake failed drill - when
  another run holds it. Its servers carry DR_DRILL_STACK, so their error mail is tagged and they
  never send a critical WhatsApp page. Before teardown it stops its own app services, but only
  when the deploy file provably names the drill's servers rather than the live ones.

  These scenarios exercise Dr::PulumiLock, Dr::DrillTeardown and DrillStack. The S3 lock listing,
  the SSH wait and the teardown itself are proven by the staging DR drill (see the qa-checklist of
  openspec/changes/fix-dr-drill-hygiene).

  # H1 — Happy path
  Scenario: A stack with no lock is free to drill
    When the Pulumi locks for "staging-ap-south-2" are classified from no lock files
    Then the stack lock state is "free"

  # X1 — Error case: the 2026-11-08 collision - a second run while the first held the lock
  Scenario: A lock held by a live process on this machine refuses the drill
    Given a Pulumi lock by "thimmaiah" on this machine with a live pid, taken 2 minutes ago
    When the Pulumi locks for "staging-ap-south-2" are classified
    Then the stack lock state is "running_here"
    And the lock message mentions "already running on this machine"

  # E2 — Edge case: a killed run leaves its lock behind
  Scenario: A lock from a dead process on this machine is reported as stale with the cancel command
    Given a Pulumi lock by "thimmaiah" on this machine with a dead pid, taken 90 minutes ago
    When the Pulumi locks for "staging-ap-south-2" are classified
    Then the stack lock state is "stale"
    And the lock message mentions "pulumi cancel --stack staging-ap-south-2"

  # E3 — Edge case: someone else's run, from another machine
  Scenario: A lock from another machine names who holds it
    Given a Pulumi lock by "ops" on host "build-box", taken 5 minutes ago
    When the Pulumi locks for "staging-ap-south-2" are classified
    Then the stack lock state is "held_elsewhere"
    And the lock message mentions "ops@build-box"

  # H2 — Happy path: the deploy file still names exactly the drill's app servers
  Scenario: Teardown stops services when the deploy file names the drill servers
    Given a deploy file naming servers "40.192.121.217" and "16.113.90.67"
    When it is checked against the drill servers "40.192.121.217" and "16.113.90.67"
    Then the deploy file targets the drill

  # X2 — Error case: back on main, the deploy file names LIVE staging
  Scenario: Teardown refuses to stop services through a deploy file naming live servers
    Given a deploy file naming servers "52.66.163.132" and "52.66.163.132"
    When it is checked against the drill servers "40.192.121.217" and "16.113.90.67"
    Then the deploy file does not target the drill

  # X3 — Error case: half drill, half something else is not the drill
  Scenario: Teardown refuses a deploy file that only partly names the drill servers
    Given a deploy file naming servers "40.192.121.217" and "52.66.163.132"
    When it is checked against the drill servers "40.192.121.217" and "16.113.90.67"
    Then the deploy file does not target the drill

  # H3 — Happy path: a drill's error mail says it is a drill
  Scenario: Error mail from a drill stack is tagged
    When the error mail prefix is built for "staging" on "altconnects.com" with DR_DRILL_STACK "ap-south-2"
    Then the error mail prefix is "[Error][DR DRILL ap-south-2] staging:(altconnects.com)"

  # E1 — Edge case: every other environment's mail is exactly as before
  Scenario: Error mail from a normal environment is unchanged
    When the error mail prefix is built for "staging" on "altconnects.com" with DR_DRILL_STACK ""
    Then the error mail prefix is "[Error] staging:(altconnects.com)"

  # E4 — Edge case: a production drill's teardown used to page WhatsApp like a real outage
  Scenario: A drill stack never sends a critical WhatsApp page
    Given critical WhatsApp alerts are switched on
    When DR_DRILL_STACK is "ap-south-2"
    Then critical WhatsApp alerts are not enabled

  # H4 — Happy path: a drill's servers carry the mark
  Scenario: Verification passes when a drill's servers are marked
    When a drill run is verified on servers with DR_DRILL_STACK "ap-south-2"
    Then the drill mark grade is "ok" mentioning "no WhatsApp pages"

  # X4 — Error case: an unmarked drill would page like a live outage
  Scenario: Verification fails when a drill's servers are not marked
    When a drill run is verified on servers with DR_DRILL_STACK ""
    Then the drill mark grade is "fail" mentioning "would page WhatsApp"

  # X5 — Error case: a recovered production marked as a drill would never page
  Scenario: Verification fails when a real recovery is marked as a drill
    When a real recovery is verified on servers with DR_DRILL_STACK "ap-south-2"
    Then the drill mark grade is "fail" mentioning "NEVER page"

  # E5 — Edge case: a real recovery, unmarked, pages as normal
  Scenario: Verification passes when a real recovery is not marked
    When a real recovery is verified on servers with DR_DRILL_STACK ""
    Then the drill mark grade is "ok" mentioning "page as normal"

  # H5 — Happy path: the teardown is recorded in the drill's own log row, adding the column once
  Scenario: A torn-down drill's teardown is recorded in its drill log row
    Given a drill log with a row for "dr_drill_in_2026_11_08_1039"
    When the teardown "services stopped · 46 resources destroyed" is recorded for "dr_drill_in_2026_11_08_1039"
    Then the drill log header ends with "| Branch | Teardown |"
    And the row for "dr_drill_in_2026_11_08_1039" ends with "| services stopped · 46 resources destroyed |"

  # E6 — Edge case: what the cell says when nothing was torn down
  Scenario Outline: The teardown cell says what happened to the stack
    When the teardown is summarised for a "<result>" run with teardown "<teardown>", stop "<stop>" and destroyed "<destroyed>"
    Then the teardown cell reads "<cell>"

    Examples:
      | result | teardown | stop    | destroyed | cell                                                             |
      | passed | yes      | stopped | 46        | services stopped · 46 resources destroyed                        |
      | passed | yes      | skipped | 46        | service stop skipped (deploy file not the drill's) · 46 resources destroyed |
      | passed | yes      | stopped | failed    | services stopped · destroy FAILED — stack still up               |
      | passed | no       |         |           | kept running (TEARDOWN not set)                                  |
      | failed | yes      |         |           | kept for diagnosis (failed run)                                  |
