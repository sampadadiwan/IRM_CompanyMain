Feature: Newcomer guidance — Getting started, What's next, check descriptions and "How we checked"
  A fund new to Compliance is led from "just switched on" to working breaches: Getting started (8 steps
  worked out from data), What's next on every page, page intros and term tooltips from one glossary, the
  section bar, the timing banner, a guide that opens at the page's section, a welcome and two reminders,
  and super-admin setup progress. Every check carries a plain-words description ("About this check") and
  every working reads "How we checked". Worked examples:
  openspec/changes/fund-compliance-monitoring/business-rules.md (group 13)

  # H80 — Happy path: a firm with an owner and an approver but no packs sees "1 of 8 done" with Attach packs current
  @rack_test
  Scenario: H80 Getting started on first visit
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    And I am signed in to compliance as "Nina"
    When I open the compliance home
    Then Getting started shows "1 of 8 done"
    And Getting started step "owner" is "done"
    And Getting started step "attach" is "current"
    And What's needed now says "Attach a rule pack to a fund."
    And the Getting started button reads "Attach a pack"

  # H81 — Happy path: attaching SEBI ticks step 2; step 3 names the unmapped inputs and the checks they block
  @rack_test
  Scenario: H81 Steps tick from data
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    When "Nina" attaches SEBI to the new firm's fund
    And I am signed in to compliance as "Nina"
    And I open the compliance home
    Then Getting started step "attach" is "done"
    And Getting started step "inputs" is "current"
    And What's needed now says "Map 2 inputs for SEBI — AIF: Sponsor/manager, estimated expenses."
    And Getting started says why "show Could not check"
    And the Getting started button reads "Map inputs"

  # H82 — Happy path: with steps 1–4 done, Run now from step 5 gives results today; step 5 ticks
  @rack_test
  Scenario: H82 First run from Getting started
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    And "Nina" attaches SEBI to the new firm's fund
    And the new firm maps its inputs
    And I am signed in to compliance as "Nina"
    When I open the compliance home
    Then Getting started step "lists" is "not_needed"
    And Getting started step "first run" is "current"
    And the Getting started button reads "Run now on Nova Fund I"
    When I press the Getting started button
    And I open the compliance home
    Then Getting started step "first run" is "done"
    And Getting started step "recipients" is "current"

  # H83 — Happy path: all 8 steps done → one line "Setup complete · Show steps"
  @rack_test
  Scenario: H83 Setup complete folds away
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And Horizon has tagged "Meera" for the compliance digest
    And every open Horizon item is assigned to "Arjun"
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then Getting started is complete

  # H84 — Happy path: a breach result offers Assign it · Request an explanation · or fix the data
  @rack_test
  Scenario: H84 What's next on a breach
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Single-investee concentration" result of "Horizon Growth Fund I"
    Then What's next says "This check is in breach. Either:"
    And What's next offers "Assign it, Request an explanation"
    And What's next notes "…or fix the data — the next run clears it by itself."

  # H85 — Happy path: Could not check names the input to map, linking to Setup
  @rack_test
  Scenario: H85 What's next on Could not check
    Given the Horizon compliance setup
    And the sponsor/manager input is unmapped
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Continuing interest — amount" result of "Horizon Growth Fund I"
    Then What's next says "Map Sponsor/manager in Setup — the next run checks again."
    And What's next offers "Map Sponsor/manager in Setup"

  # H86 — Happy path: home says which run the results come from and when the next one is
  @rack_test
  Scenario: H86 Timing banner
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And the compliance date is "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then the timing banner says "Results from the 02:00 IST run on 05/11/2026 · next run 06/11/2026 02:00 IST"

  # H87 — Happy path: the firm's first setup sends company admins and tagged users one welcome
  Scenario: H87 Welcome notice
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    Then "Nina" got the compliance notice "Compliance is on for Nova Capital — start with Getting started (8 steps)" 1 time

  # H88 — Happy path: the item's status carries the glossary's words as a tooltip
  @rack_test
  Scenario: H88 Term tooltip
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And "Arjun" explains the "Single-investee concentration" item with "Temporary — follow-on call due 30 Nov"
    And "Rahul" approves the explanation of the "Single-investee concentration" item
    And I am signed in to compliance as "Meera"
    When I open the "Single-investee concentration" register item of "Horizon Growth Fund I"
    Then the page has the tooltip "An approver accepted this breach with a reason. It reopens if the figure gets worse."

  # H89 — Happy path: every compliance page shows the section bar with counts
  @rack_test
  Scenario: H89 Section bar with counts
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the register page
    Then the section bar shows "Home Register"
    And the section bar shows "Duties"
    And the section bar shows "Facts to confirm"
    And the section bar shows the open item count on Register

  # E200 — Edge case: the section bar is lazy tabs on the Compliance hub — the Register pane loads its own content from its frame src, and ?tab= opens it
  @rack_test
  Scenario: E200 Section bar loads sections in place
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the compliance hub at the "register" tab
    Then the "register" section pill is active on the hub
    And the "register" pane is a lazy frame loading the register page
    When the "register" pane's frame loads
    Then the frame answer holds the register inside the "register" hub frame, without a section bar
    When I open the compliance home
    Then the home pane is drawn inline with the "duties" pane as a lazy frame

  @rack_test
  Scenario: H90 Guide opens at the page's section
    Given the Horizon compliance setup
    And I am signed in to compliance as "Meera"
    When I open the register page
    Then the guide icon opens the guide at "the-register"

  # H91 — Happy path: a result opens with "About this check" — the SEBI check's plain-words description
  @rack_test
  Scenario: H91 About this check
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Single-investee concentration" result of "Horizon Growth Fund I"
    Then About this check says "SEBI caps it at 25% so one company's failure cannot sink the fund"
    When I open the "Single-investee concentration" register item of "Horizon Growth Fund I"
    Then About this check says "Usually breached by a follow-on investment made before new capital is raised"

  # H92 — Happy path: the working is "How we checked", naming the 02:00 run — or Run now's own time
  @rack_test
  Scenario: H92 How we checked
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Single-investee concentration" result of "Horizon Growth Fund I"
    Then the compliance page shows "How we checked"
    And How we checked says "Step by step, from your records as they stood at the 02:00 IST run on 05/11/2026."
    And the compliance page does not show "Working"

  # E180 — Edge case: a newly attached pack with an unmapped input reopens step 3
  @rack_test
  Scenario: E180 Step goes back
    Given the Horizon compliance setup
    And Horizon attaches a pack needing the unmapped input "board cap"
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then Getting started step "inputs" is "current"
    And What's needed now says "Map 1 input for Horizon — board rules: board cap."

  # E181 — Edge case: no attached check reads a reference list → step 4 "Not needed for your packs"
  @rack_test
  Scenario: E181 Reference list not needed
    Given the Horizon compliance setup
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then Getting started step "lists" is "not_needed"

  # E182 — Edge case: a viewer sees the steps, no buttons, and who can act
  @rack_test
  Scenario: E182 Viewer sees steps, not buttons
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    And I am signed in to compliance as "Ravi"
    When I open the compliance home
    Then Getting started step "attach" is "current"
    And Getting started has no button and says "Ask Nina Test (compliance owner) to do this."

  # E183 — Edge case: one eligible approver → step 1 done, with the Self-approved note
  @rack_test
  Scenario: E183 Single approver
    Given a new firm "Lone Capital" with Compliance switched on and one user "Lena"
    And I am signed in to compliance as "Lena"
    When I open the compliance home
    Then Getting started step "owner" is "done"
    And Getting started notes "Only you can approve — your approvals will be labelled Self-approved."

  # E184 — Edge case: no runs yet → "No results yet — the first run is tonight"
  @rack_test
  Scenario: E184 Never run
    Given the Horizon compliance setup
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then the timing banner says "No results yet — the first run is tonight at 02:00 IST."

  # E185 — Edge case: last success 05/11, 06/11 run failed → amber "may be out of date"
  @rack_test
  Scenario: E185 Stale results
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And the nightly compliance run on "2026-11-06" fails
    And the compliance date is "2026-11-06"
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then the timing banner says "Last successful run 05/11/2026 02:00 IST — results may be out of date."
    And the timing banner is amber

  # E186 — Edge case: an approver is offered Approve and Reject for Meera's explanation
  @rack_test
  Scenario: E186 Approver's next step
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Temporary — follow-on call due 30 Nov"
    And I am signed in to compliance as "Rahul"
    When I open the "Single-investee concentration" register item of "Horizon Growth Fund I"
    Then What's next says "Approve or reject Meera Test's explanation."
    And What's next offers "Approve, Reject"

  # E187 — Edge case: the requester is told who will decide, with no Approve button
  @rack_test
  Scenario: E187 Requester's next step
    Given the Horizon compliance setup
    And the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Temporary — follow-on call due 30 Nov"
    And I am signed in to compliance as "Meera"
    When I open the "Single-investee concentration" register item of "Horizon Growth Fund I"
    Then What's next says "Waiting for an approver"
    And What's next offers no "Approve"

  # E188 — Edge case: an empty register says when the next run is
  @rack_test
  Scenario: E188 Empty register
    Given the Horizon compliance setup
    And I am signed in to compliance as "Meera"
    When I open the register page
    Then What's next says "Nothing open. The next run is tonight at 02:00 IST."

  # E189 — Edge case: the owner is reminded on day 7 and day 21 only, while setup is incomplete
  Scenario: E189 Reminders stop
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    When the hourly compliance tick happens 7 days after setup at 08:00 IST
    And the hourly compliance tick happens 21 days after setup at 08:00 IST
    And the hourly compliance tick happens 35 days after setup at 08:00 IST
    Then "Nina" got the compliance notice "Getting started: 1 of 8 done — next: Attach packs" 2 times

  # E190 — Edge case: saving the setup again sends no second welcome
  Scenario: E190 Welcome sent once
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    When the new firm saves its setup again
    Then "Nina" got the compliance notice "Compliance is on for Nova Capital" 1 time

  # E191 — Edge case: monitoring stays refused (X15) while an input is missing; step 3 stays current
  @rack_test
  Scenario: E191 Monitoring on before inputs mapped
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    And "Nina" attaches SEBI to the new firm's fund
    When "Nina" turns monitoring on for the new firm
    Then the setup is refused with "missing — Sponsor/manager"
    And I am signed in to compliance as "Nina"
    When I open the compliance home
    Then Getting started step "inputs" is "current"
    And Getting started step "monitoring" is "todo"

  # E192 — Edge case: a super admin sees each firm's setup progress
  @rack_test
  Scenario: E192 Super admin sees who is stuck
    Given a new firm "Nova Capital" with Compliance switched on, owner "Nina" and approver "Ravi"
    And "Sam" is a CapHive super admin
    And I am signed in to compliance as "Sam"
    When I open the customer setup list
    Then the compliance page shows "Nova Capital"
    And the compliance page shows "1 of 8"
    And the compliance page shows "Attach packs"

  # E193 — Edge case: a draft lists the check with no description; publishing it is refused
  @rack_test
  Scenario: E193 Publish needs a description on every check
    Given the Horizon compliance setup
    And Meera has a draft v2 of the fund agreement pack
    And the fund agreement draft check "Single-sector limit" has no description
    And I am signed in to compliance as "Meera"
    When I open the Checks tab of the fund agreement draft
    Then the compliance page shows "1 check has no description: Single-sector limit"
    When Meera publishes the fund agreement draft
    Then the version publish is refused with "Add a description to every check: Single-sector limit"

  # E194 — Edge case: the backfill writes only descriptions into a SEBI v1 published without them
  Scenario: E194 Backfill descriptions into published versions
    Given the Horizon compliance setup
    And SEBI v1 was published before descriptions existed
    When the description backfill runs as a dry run
    Then the backfill reports "SEBI — AIF v1: 10 checks to describe"
    And SEBI v1 is unchanged
    When the description backfill runs with EXECUTE=1
    Then every SEBI v1 check has its description and nothing else changed

  # E195 — Edge case: a needs-review summary appears once; the box only says why a person must look
  @rack_test
  Scenario: E195 Needs-review summary shown once
    Given the Horizon compliance setup
    And a needs-review result of "Single-investee concentration" on "Horizon Growth Fund I" with the summary "1 of 10 OK · 4 to look at · 5 without a document"
    And I am signed in to compliance as "Meera"
    When I open that result
    Then the page shows "1 of 10 OK · 4 to look at · 5 without a document" once
    And the compliance page shows "A person must look at this. Rules cannot decide it"

  # E196 — Edge case: records before the check started are described in words, with a link to them
  @rack_test
  Scenario: E196 Records before the check started
    Given the Horizon compliance setup
    And "Horizon Growth Fund I" also carries the fund agreement pack
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "IC note for every investment" result of "Horizon Growth Fund I"
    Then the compliance page shows "3 investments made before this check started are not checked"
    And the earlier records link opens the investments before "2026-04-01"
    And the compliance page does not show "earlier not checked"

  # E197 — Edge case: a small gap reads in crores ("₹0.15 cr"), never "₹15,00,000"
  @rack_test
  Scenario: E197 Small amounts in crores
    Given the Horizon compliance setup
    And the sponsor's commitment to "Horizon Growth Fund I" is ₹4.85 cr
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Continuing interest — amount" result of "Horizon Growth Fund I"
    Then the compliance page shows "needs ₹0.15 cr more"
    And the compliance page does not show "₹15,00,000"

  # E198 — Edge case: after Mark done the cards follow the grid's filter, not the firm-wide totals
  @rack_test
  Scenario: E198 Duty cards follow the filter
    Given the Horizon compliance setup
    And Horizon also carries SEBI on "Horizon Seed Fund"
    And the nightly compliance run happens on "2026-11-05" for "Horizon Seed Fund"
    And the nightly compliance run happens on "2026-11-05"
    And a duty of "Horizon Growth Fund I" is due on "2026-10-15"
    And I am signed in to compliance as "Meera"
    When I mark the "Quarterly SEBI report filed" duty done from a grid filtered to "Horizon Seed Fund"
    Then the refreshed duty cards count only "Horizon Seed Fund" duties

  # E199 — Edge case: the AI's description is shown, edited before save, and saved with the check
  @rack_test
  Scenario: E199 AI draft carries a description
    Given the Horizon compliance setup
    And Describe in words is on for Horizon
    And Meera has a draft v2 of the fund agreement pack
    And the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "citation": "LPA cl. 8.2",
       "description": "The most invested in any one sector. Usually breached by several deals in one industry.",
       "figure": {"measure": "cost_per_sector"}, "divided_by": {"measure": "investable_funds"},
       "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector — LPA clause 8.2"
    Then the draft description reads "The most invested in any one sector."
    When I change the draft description to "No more than 15% of investable funds in one sector."
    And I test-run the draft check on "Horizon Growth Fund I"
    And I save the draft check
    Then the saved check "Single-sector limit (AI)" is described as "No more than 15% of investable funds in one sector."

  # X94 — Error case: a published version whose rules differ from its file is skipped, never touched
  Scenario: X94 Backfill never changes a rule
    Given the Horizon compliance setup
    And SEBI v1's concentration limit was edited after loading
    When the description backfill runs with EXECUTE=1
    Then the backfill reports "SEBI — AIF v1: rules differ from the seed file — not touched"
    And SEBI v1 is unchanged

  # E201 — Edge case: clicking a step's circle opens its popup, as on other journeys — "Map inputs" lists each input with mapped / not mapped and the checks a missing one blocks; "Owner & approvers" shows the owner and approvers
  @rack_test
  Scenario: E201 Step popups
    Given the Horizon compliance setup
    And the sponsor/manager input is unmapped
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then the "inputs" step circle opens its popup
    When I open the Getting started popup for "inputs"
    Then the step popup is titled "Map inputs"
    And the step popup lists "Sponsor/manager (SEBI — AIF): Not mapped — blocks"
    And the step popup has the button "Map inputs"
    When I open the Getting started popup for "owner"
    Then the step popup is titled "Owner & approvers"
    And the step popup lists "Owner: Meera"

  # E202 — Edge case: minimising Getting started is remembered for the user — the steps stay folded under the header on the next visit
  @rack_test
  Scenario: E202 Minimise remembered
    Given the Horizon compliance setup
    And the sponsor/manager input is unmapped
    And I am signed in to compliance as "Meera"
    When I open the compliance home
    Then the Getting started steps are expanded
    When I minimise Getting started
    And I open the compliance home
    Then the Getting started steps are folded under the header
    And Getting started shows "of 8 done"

