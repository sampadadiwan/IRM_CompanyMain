# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

## 1. Preload associations on the Account Entries list

- [x] 1.1 In `app/packs/funds/capital_commitments/services/account_entry_list.rb`, change `includes(:fund, :investor, capital_commitment: :investor_kyc)` to `preload(:fund, :investor, :investor_kyc, capital_commitment: :investor_kyc)`. The extra top-level `:investor_kyc` is needed because list rows read `account_entry.investor_kyc`, a `has_one :through` that the nested preload does not populate (an N+1 before this change too).
- [x] 1.2 Check the list view, pivot and time-series paths for reads that depended on the eager-load join. Findings: pivot only plucks (preload never fires, its `.includes(:fund)` is stripped by `except(:includes)`); time-series reads `name`, `reporting_date`, `amount` only; row views read preloaded associations.
- [x] 1.3 Add `features/step_definitions/account_entries_index_query_steps.rb`: capture SELECTs on `account_entries` during a page load, reusing the pattern in `features/step_definitions/account_entry_report_performance.rb`.
- [x] 1.4 Write `features/fund/account_entries_index_query.feature` covering H1, H2, E1, E2, E3, X1 from design.md. Run it with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/account_entries_index_query.feature` and confirm it passes before starting phase 2.

## 2. Open the list on the first fund

- [x] 2.1 In `AccountEntryList`, add `ensure_default_fund` right after `ensure_default_filters`: when the request has no top-level `fund_id` and no `fund_id` condition in `params[:q]`, set `params[:fund_id]` to the first fund of `Pundit.policy_scope!(current_user, Fund)` in `Fund.ordered` order, so the top Fund Name filter shows it. Verify with `grep -n "ensure_default_fund" app/packs/funds/capital_commitments/services/account_entry_list.rb`.
- [x] 2.2 The portfolio investment page links to the list with only `parent_type` and `parent_id`. Add `fund_id: portfolio_investment.fund_id` to that link in `app/packs/funds/portfolios/views/portfolio_investments/_details.html.erb` so it keeps listing its own entries. Every other in-app link already passes `fund_id`.
- [x] 2.2a Skip the default when the request is narrowed by `capital_commitment_id`, `investor_id`, `import_upload_id`, `folio_id` or `parent_id` (top-level or in `q`), so the import upload, investor and folio pages keep listing every fund. Show a notice naming the fund when the default was applied (`Result#fund_defaulted`).
- [x] 2.2c `AccountEntriesController#destroy` redirects to the entry's fund list; drop the redundant `.includes(:fund)` in the pivot.
- [x] 2.2b A blank `fund_id` (the "All Funds" option, `fund_id=`) is a deliberate choice: `ensure_default_fund` returns when the `fund_id` key is present. Delete Results and Export All links name the shown fund (covered in `account_entries_default_fund.feature`).
- [x] 2.3 Add `features/step_definitions/account_entries_default_fund_steps.rb` and write `features/fund/account_entries_default_fund.feature` covering H3, H4, E4, E5, E6, X2 from design.md. Run it with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/account_entries_default_fund.feature` and confirm it passes before starting phase 3.

## 3. Verify and release

- [x] 3.1 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/account_entry_report_performance.feature features/fund/account_entries.feature` and the two new features. Run `bundle exec rubocop` on the changed Ruby files clean.
- [ ] 3.2 On a production replica, run `EXPLAIN ANALYZE` on the new main query for the large entity with a single `fund_id`, and with several funds, and record whether "Using temporary" and the 4M-row scan remain. If they do, open follow-ups for the open questions in design.md (distinct, entity filter, limiting funds).
  Run it in a rails console on the **replica**, never the primary. `EXPLAIN ANALYZE` executes the query (MySQL 8.0.18+), so All Funds, the query that built the 13 GB temp table, gets plain `EXPLAIN` only.

  ```ruby
  user = User.find(<admin user id of the large entity>)
  fund = Fund.find(<one large fund id>)

  # Same relation the page builds, not executed here
  build = lambda do |extra|
    params = ActiveSupport::HashWithIndifferentAccess.new({ per_page: 20 }.merge(extra))
    AccountEntryList.call(user, params).account_entries.limit(21)   # per_page + 1, as pagy_countless does
  end

  conn = ActiveRecord::Base.connection
  conn.execute("SET SESSION MAX_EXECUTION_TIME = 30000")             # 30s safety cap

  # 1. Single fund: safe to run
  puts conn.select_rows("EXPLAIN ANALYZE #{build.call(fund_id: fund.id).to_sql}").flatten

  # 2. Several funds: plan only
  ids = user.entity.funds.limit(3).pluck(:id)
  puts conn.select_rows("EXPLAIN #{build.call(q: { fund_id_in: ids }).to_sql}").map(&:inspect)

  # 3. All Funds (fund_id key present but blank): plan only
  puts conn.select_rows("EXPLAIN #{build.call(fund_id: '').to_sql}").map(&:inspect)
  ```

  What to look for: single fund uses a `fund_id` index, no "Using temporary" or "Using filesort", small actual rows and time. Several funds and All Funds will probably still show temporary and filesort because of `.distinct`; that is the expected remaining cost, and a row estimate in the millions confirms the follow-ups. `EXPLAIN FORMAT=TREE` is more readable. Record the three results here.
- [ ] 3.3 After deploy, run qa-checklist.md on a deployed build and record the sign-off (for QA, not the apply agent).
