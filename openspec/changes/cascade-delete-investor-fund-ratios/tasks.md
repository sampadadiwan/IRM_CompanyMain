# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Cascade delete and popup

- [x] 1.1 Add `has_many :fund_ratios, class_name: "FundRatio", as: :owner, dependent: :destroy` to `Investor` (lld: File Map, Method Contracts). Verify: in a console, `Investor.reflect_on_association(:fund_ratios)` is present and destroying an investor soft-deletes its ratios.
- [x] 1.2 Add `data-title` and `data-msg` to the delete button in `investors/show.html.erb`; the message is "Deleting this investor will also delete its N associated fund ratios. Proceed?" (singular, without a number, for exactly one ratio" with only the count interpolated, and the investor name goes in the title only (lld: Security Review). Verify: the page renders and the popup shows the text.
- [x] 1.3 Write `features/fund/investor_fund_ratio_cleanup.feature` covering H1, H2, E1, E2, E3, E4 (add the new steps listed in lld: Test Plumbing). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/investor_fund_ratio_cleanup.feature` and confirm it passes before starting phase 2.

## 2. Widget guard

- [x] 2.1 In `_irr.html.erb`, add `.select(&:owner)` as the last relation call before `group_by` (lld: Queries and Indexes). Verify: the widget renders with an orphaned ratio present.
- [x] 2.2 In `_company_ratios_aggregate.html.erb`, skip ratios without an owner before mapping `fr.owner.name` (`FundRatioList` already preloads `owner`). Also guard `PortfolioHelper#portfolio_last_xirr`, which the `_irr` chart calls and which crashed on the same orphans (found while writing E5). Verify: both render with an orphaned ratio present.
- [x] 2.3 Extend `features/fund/investor_fund_ratio_cleanup.feature` with E5 (E6, the company ratios widget, is manual-only: it could not be reached from a feature). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/investor_fund_ratio_cleanup.feature` and confirm it passes before starting phase 3.

## 3. Orphan clean-up and wrap-up

- [x] 3.1 Document the orphan clean-up snippet, with dry-run count, covering both missing and soft-deleted investors (lld: Configuration and Rollout), under `docs/operations/troubleshooting/`. Verify: a developer review of the query.
- [x] 3.2 Extend `features/fund/investor_fund_ratio_cleanup.feature` with E7 using the snippet's query. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/investor_fund_ratio_cleanup.feature` until green, then run `bundle exec rubocop app/packs/core/investors/models/investor.rb`.
- [ ] 3.3 Run `qa-checklist.md` on a deployed build and record the sign-off (for QA, not for the apply agent).
