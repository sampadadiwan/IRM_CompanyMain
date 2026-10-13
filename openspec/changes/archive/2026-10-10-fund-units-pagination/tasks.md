# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Server-side paging (③ Pager)

- [x] 1.1 In `FundUnitsController#fetch_rows`, paginate the `FundUnitList` result with `pagy`, only when `params[:all]` is blank and the request is HTML; clamp `page` into `1..total_pages`, default `per_page` to 25 and cap at 500 (LLD: Method Contracts). Verify with `bin/rails runner` or a browser load that `/fund_units` returns 25 rows for a large set.
- [x] 1.1a In `FundUnitList#call`, apply a default `issue_date desc, id desc` order only when the ransack query has no sort (LLD: Queries and Indexes). Verify the unit with the latest issue date is first on `/fund_units`.
- [x] 1.2 Confirm json and xlsx responses still receive the unpaged relation and that `@pagy` is nil for them (LLD: Controllers, Params and Responses). Verify by requesting `/fund_units.xlsx?all=true`.
- [x] 1.3 Add the new step definitions to `features/step_definitions/fund_unit.rb` (create N fund units, assert row count, request a given page) (LLD: Test Plumbing).
- [x] 1.4 Write `features/fund/fund_unit_pagination.feature` covering H1, H3, H4, H6, E1, E2, E3, X1 (row counts, latest issue date first, filters before paging, download not paginated, empty/single page, out-of-range page). Run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_unit_pagination.feature`
      and confirm it passes before starting phase 2. (Scenarios asserting pager text wait for phase 2.)

## 2. Pager UI (④ List view, ⑤ Page links)

- [x] 2.1 In `fund_units/_index.html.erb` remove the `jqDataTable` class from the table (LLD: File Map). Verify in the browser that the table shows one set of controls.
- [x] 2.2 Below the table render `pagy_info` and `pagy_bootstrap_nav(@pagy, anchor_string: ...)` with `data-turbo-frame` set to `with_frame("fund_units_frame")`, shown only when rows exist and `@pagy` is set. Verify page 2 loads inside the frame on `/fund_units` and on an investor screen.
- [x] 2.3 Extend `features/fund/fund_unit_pagination.feature` with H1 summary and links text, H2, E1 summary-without-links and E2 no-pager assertions, E4 filter kept across pages, and H5 (embedded list pages in place, page links keep the investor filter). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_unit_pagination.feature`
      until green before starting phase 3.

## 3. Search and sorting (① Filter, search, sort)

- [x] 3.1 In `FundUnitList#call`, apply `params[:search]` as a ransack or-of-`cont` predicate over unit type, reason and folio id, merged into the relation and not stored in `@q` (LLD: Queries and Indexes). Verify `/fund_units?search=<folio>` returns only that folio's units and the filter panel shows no extra condition.
- [x] 3.2 In `fund_units/_index.html.erb` add a Search box above the table: a GET form inside the frame, targeted at `with_frame("fund_units_frame")`, carrying the current query as hidden fields but not `page` or `search` (LLD: File Map). Verify typing and pressing Enter refreshes only the list.
- [x] 3.3 Replace the `<th>` texts with `sort_link` for the sortable columns, with `data-turbo-frame` set from `with_frame`, dropping `page` so a sort shows page 1 (LLD: Queries and Indexes, Sort). Verify clicking a header sorts and the arrow flips.
- [x] 3.4 Drop `jqDataTable` and `data-controller="datatable"` from the partial. Add `fund_units` to the lazy-frame list in `import_uploads/show.html.erb` so the import upload page loads the index action (design decisions 3 and 7). Scenario E9 covers it; the import scenarios in `features/fund/fund_unit.feature` still pass.
- [x] 3.5 Extend `features/fund/fund_unit_pagination.feature` with H7, H8, E5, E6, E7, E8 and the steps in LLD: Test Plumbing. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_unit_pagination.feature`
      until green before starting phase 4.

## 4. Regression and verification

- [x] 4.1 Re-run the existing fund unit features that may assume every row is visible, and fix any scenario that breaks: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_unit.feature`, plus the fund-unit step-file users (`features/fund/fund_access.feature`, the fund_unit_transfer and fund_units_delete_guard features if present).
- [x] 4.2 Run `bundle exec rubocop app/packs/funds/funds/controllers/fund_units_controller.rb features/step_definitions/fund_unit.rb` and fix offences; run `bundle exec brakeman` since a controller changed.
- [x] 4.3 Write the final feature confirmation: run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_unit_pagination.feature features/fund/fund_unit.feature` together and confirm green.
- [ ] 4.4 Run `qa-checklist.md` on a deployed build and record the sign-off (for QA, not for the apply agent).
