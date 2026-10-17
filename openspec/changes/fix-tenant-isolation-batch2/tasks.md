# Tasks

> **Reproduce first**, then fix. Every cucumber run needs a fresh `TEST_ENV_NUMBER` and Redis on 6379.

## 1. Reproduce

- [x] 1.1 Write `features/security/tenant_isolation_batch2.feature` (B1, B3, B4 rows with `# <ID> — …`
      comments) and its steps. Verify: `--dry-run` clean.
- [x] 1.2 Run against current code: 11 of 14 fail; B3-H, B3-4, B4-5-H pass.

## 2. Fix

- [x] 2.1 B1 `EntityPolicy#full_details?`, page and JSON.
- [x] 2.2 B3 `investor_list_filter` (approvals, sales), document and folder list filters.
- [x] 2.3 B4-1 fund ratios; B4-2 KYC; B4-3 deal investor.
- [x] 2.4 B4-4 `PolicyScopedSearch` on the search actions, typeahead, task-search query.
- [x] 2.5 B4-5 MCP entity check; B4-6 role checks.
- [x] 2.6 Run the feature: 14/14 pass.

## 3. Regression and cleanup

- [x] 3.1 Regression (pcuc, 4 workers) over the Blast Radius features: 824/830. The 6 failures all
      fail identically on clean `main` or pass alone: `rack_attack_404_blocking.feature:87,97`,
      `lp_folio_visibility.feature:37`, `lp_company_dashboard.feature:175`,
      `lp_portfolio_view_setting.feature:23` (same on `main`), `document.feature:63` (passes alone).
- [x] 3.2 Independent review of the diff for broken legitimate flows; follow-ups applied (report: Fix).
- [x] 3.3 `bundle exec rubocop` on the changed files: no new offences.
