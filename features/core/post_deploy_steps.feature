@rack_test
Feature: Post-deploy steps — every deploy asks each environment's open steps
  Each change writes post_deploy_steps/<change>.md with a section per environment. After every deploy,
  post_deploy:checklist asks the deployer to answer each step the deployed release has for that environment and
  that it has not logged as done: "done", or "skip <reason>" (asked again next deploy).
  Format and behaviour: post_deploy_steps/README.md · code: lib/post_deploy_steps.rb,
  lib/capistrano/tasks/post_deploy.rake.

  # ── Drift guards over the real folder ─────────────────────────────────────────

  # PD1 — Guard: every file in post_deploy_steps/ is well-formed, so no step is silently dropped by a typo
  Scenario: PD1 Every post-deploy steps file is well-formed
    Then every file in post_deploy_steps is well-formed

  # PD2 — Guard: an OpenSpec change archived from 2026-11-11 (when this rule began) has its post-deploy steps file
  Scenario: PD2 Every archived change has a post-deploy steps file
    Then every OpenSpec change archived since "2026-11-11" has a post-deploy steps file

  # ── Happy path ────────────────────────────────────────────────────────────────

  # H1 — Happy path: an environment gets the "all" steps, its region group and its own section, nothing else
  Scenario: H1 Steps are chosen per environment
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## all
      ### tell-support — Tell support about the release

      ## production
      ### flag-on — Switch the flag on
      ```
      FLAG=1
      ```

      ## production_us
      ### us-only — US-only check

      ## staging_in
      ### qa — Run the QA checklist
      """
    Then the open post-deploy steps for "production_in" are "alpha#tell-support, alpha#flag-on"
    And the open post-deploy steps for "production_us" are "alpha#tell-support, alpha#flag-on, alpha#us-only"
    And the open post-deploy steps for "staging_in" are "alpha#tell-support, alpha#qa"
    And the post-deploy step "alpha#flag-on" has the instructions "FLAG=1"

  # H2 — Happy path: answering "done" in one region closes the step there only; the other region still asks it
  Scenario: H2 A done step is not asked again in that environment
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## production
      ### flag-on — Switch the flag on
      ### report — Run the report
      """
    When the deployer answers the "production_in" checklist with:
      | answer |
      | done   |
      | done   |
    Then the post-deploy log records "alpha#flag-on" as "done" for "production_in"
    And the open post-deploy steps for "production_in" are ""
    And the open post-deploy steps for "production_us" are "alpha#flag-on, alpha#report"

  # H3 — Happy path: a skip keeps its reason and the step is asked again on the next deploy
  Scenario: H3 A skipped step is asked again
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## production_in
      ### flag-on — Switch the flag on
      ### thresholds — Tune thresholds after a few weeks
      """
    When the deployer answers the "production_in" checklist with:
      | answer                    |
      | done                      |
      | skip not yet, deployed 10 |
    Then the post-deploy log records "alpha#thresholds" as "skip" for "production_in" with the reason "not yet, deployed 10"
    And the open post-deploy steps for "production_in" are "alpha#thresholds"

  # H4 — Happy path: a change with nothing to do says so, and adds no steps
  Scenario: H4 A file with nothing to do
    Given a post-deploy steps file "beta" with:
      """
      # Post-deploy steps — beta

      None — code only; nothing to switch on or run after deploy.
      """
    Then the post-deploy steps files are well-formed
    And the open post-deploy steps for "production_in" are ""

  # ── Edge cases ────────────────────────────────────────────────────────────────

  # E1 — Edge case: "skip" without a reason, or an unknown answer, is asked again until it is "done" or has a reason
  Scenario: E1 Unclear answers are asked again
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## all
      ### flag-on — Switch the flag on
      """
    When the deployer answers the "staging_in" checklist with:
      | answer |
      | skip   |
      | maybe  |
      | done   |
    Then the checklist said "A skip needs a reason"
    And the checklist said "Not understood."
    And the post-deploy log records "alpha#flag-on" as "done" for "staging_in"

  # E2 — Edge case: stopping half-way (end of input) keeps the answers already given; the rest stay open
  Scenario: E2 Stopping half-way keeps earlier answers
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## all
      ### one — First step
      ### two — Second step
      """
    When the deployer answers the "production_in" checklist with:
      | answer |
      | done   |
    Then the checklist stopped before every step was answered
    And the open post-deploy steps for "production_in" are "alpha#two"

  # E3 — Edge case: steps from two changes (e.g. a skipped release and this one) are all asked, in file order
  Scenario: E3 Steps from more than one change are all asked
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## production
      ### a-step — From the earlier release
      """
    And a post-deploy steps file "gamma" with:
      """
      # Post-deploy steps — gamma

      ## production_us
      ### g-step — From this release
      """
    Then the open post-deploy steps for "production_us" are "alpha#a-step, gamma#g-step"

  # ── Error cases ───────────────────────────────────────────────────────────────

  # X1 — Error case: format mistakes are reported, so a typo can't silently drop a step
  Scenario Outline: X1 Format mistakes are reported
    Given a post-deploy steps file "bad" with:
      """
      <text>
      """
    Then linting the post-deploy steps reports "<error>"

    Examples:
      | text                                                                                    | error                               |
      | # Post-deploy steps — bad\n## prod_in\n### a — A                                        | unknown section                     |
      | # Post-deploy steps — bad\n## all\n### Flag On — A                                      | step heading must read              |
      | # Post-deploy steps — bad\n## all\n### a — A\n### a — B                                 | is used more than once              |
      | # Post-deploy steps — bad\nSome text but no steps                                       | no steps                            |
      | # Post-deploy steps — bad\nNone — nothing\n## all\n### a — A                            | has steps and a                     |
      | ## all\n### a — A                                                                       | the file needs a                    |
      | # Post-deploy steps — bad\n### a — A                                                    | is not under an environment section |

  # X2 — Error case: no terminal to answer (e.g. a CI deploy): the open steps and the command to answer them are shown
  Scenario: X2 Nobody to answer
    Given a post-deploy steps file "alpha" with:
      """
      # Post-deploy steps — alpha

      ## production_in
      ### flag-on — Switch the flag on
      """
    Then the unanswered message for "production_in" lists "alpha#flag-on: Switch the flag on"
    And the unanswered message for "production_in" says "bundle exec cap production_in post_deploy:checklist"
