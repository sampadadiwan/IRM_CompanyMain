# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> Minimal change: there is no lld.md, so each task names the design.md card it implements.
> Worked-example IDs are from [design.md § Worked examples](design.md#worked-examples).

## 1. KYC on the order and the folio (cards ①, ②)

- [x] 1.1 Migration adding nullable `dealing_orders.investor_kyc_id` (FK → `investor_kycs`, indexed); add it to `db/schema.rb` and `db/schema_test.rb` by hand. `DealingOrder belongs_to :investor_kyc, optional: true`. Verify: `bin/rails runner 'p DealingOrder.reflect_on_association(:investor_kyc)'` prints the association (design § Data model)
- [x] 1.2 `OrderEligibility`: the KYC rules from card ①. A folio on the order with no KYC → refuse (X4). For a new folio: 0 approved KYCs → refuse (X1); 1 → use it; ≥ 2 → a pick from that investor's approved KYCs is required (X2, X3). Set `order.investor_kyc_id`, copying the folio's KYC for top-ups and redemptions (H3, E5). Verify: `bin/rails runner` against a fixture order prints the expected error or KYC id
- [x] 1.3 `Evergreen::OrdersController#build_order` permits `investor_kyc_id`; `orders/new.html.erb` shows the **Investing entity** select only for subscriptions without a folio when the investor has ≥ 2 approved KYCs (H2, E2, E3). Verify: open the wizard in dev for an investor with two approved KYCs and see the select
- [x] 1.4 `ImportDealingOrder`: optional "Investing Entity" column matched by KYC full name within the investor; blank → the single approved KYC (E4). Verify: import a two-row sample in dev
- [x] 1.5 `FolioOpener.open_folio` sets `investor_kyc_id` from the order and raises `FolioOpener::Error` when the order has none (H1, E1, X5). Verify: phase feature below
- [x] 1.6 Write `features/fund/evergreen/folio_kyc_orders.feature` (header links design.md#worked-examples) with one scenario per H1, H2, H3, E1, E2, E3, E4, E5, X1, X2, X3, X4, X5, each with its `# ID — …` comment. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/folio_kyc_orders.feature` until green before starting phase 2

## 2. Link KYC to existing folios (card ③)

- [x] 2.1 `Evergreen::FoliosController#link_kyc` + route `PATCH /funds/:fund_id/evergreen/folios/:id/link_kyc`: authorize `update?`; refuse an already-linked folio (X13) or a KYC that isn't one of the investor's approved KYCs (X12); save with `update!`. Verify: `bin/rails routes | grep link_kyc`
- [x] 2.2 Partial `folios/_investing_entity` in the details card: read-only name when linked; picker + Link for update users when not linked; "approve a KYC first" when the investor has none; **No KYC linked** badge by the title (H8, E6, X14). Verify: open an unlinked folio in dev
- [x] 2.3 `lib/tasks/evergreen_folio_kyc.rake` `evergreen:link_folio_kycs`: dry run by default, `EXECUTE=1` writes, `FUND_ID=` filter; links folios with exactly one approved KYC via `update!` and lists the rest (H6, E7, E8, E9). Verify: dry run in dev prints the list and changes nothing
- [x] 2.4 Write `features/fund/evergreen/folio_kyc_link.feature` with one scenario per H6, H8, E6, E7, E8, E9, X12, X13, X14. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/folio_kyc_link.feature` until green before starting phase 3

## 3. Generate, review and read statements (cards ④–⑦)

- [x] 3.1 `Evergreen::StatementsController#new/#create` + routes: folio scope authorizes `CapitalCommitmentPolicy#generate_soa?`, fund scope `FundPolicy#allocate?`; validates dates (start ≤ end) and that the template belongs to the fund or folio; queues `CapitalCommitmentSoaJob.perform_later(fund.id, folio_id_or_nil, start, end, user.id, template_id:)` (H4, H5, E10, E11, E12, X6, X7, X8, X9). Verify: `bin/rails routes | grep evergreen_statements`
- [x] 3.2 `_generate_statements_modal` (Bootstrap modal, `f.date_field`, info line) and the buttons: **Generate statement** on `folios/show` (disabled with tooltip when no verified KYC, X10) and **Generate statements** on `investors/index`. Verify: open both pages in dev
- [x] 3.3 `Evergreen::FoliosController#show`: GP with update sees generated, unapproved documents with a `badge bg-warning-subtle text-warning` "Generated · awaiting approval"; others keep `exclude_generated_unapproved` (H5, E17). Verify: phase feature below
- [x] 3.4 Sample `public/sample_uploads/Evergreen Statement Template.docx` with the `evergreen.*` fields and remittance / distribution-payment loops from card ⑤, and no `committed_amounts`; link it from the modal's "no template" message (X7). Verify: generating with it in dev produces a PDF with the H4 figures
- [x] 3.5 Write `features/fund/evergreen/folio_statements.feature` with one scenario per H4, H5, H7, E10, E11, E12, E13, E14, E15, E16, E17, X6, X7, X8, X9, X10, X11. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/folio_statements.feature` until green

## 4. NAV from the fund's real portfolio (asked during apply)

- [x] 4.1 Steps that buy / sell holdings through `PortfolioInvestmentCreate` and add `Valuation`s, with no `NavInputs` stub. Verify: phase feature below
- [x] 4.2 `lib/tasks/evergreen_demo_portfolio.rake` `evergreen:seed_demo_portfolio` (dry run unless `EXECUTE=1`, refuses production) and run it on test fund 343. Verify: a NAV drafted for 31 Oct 2026 in a rolled-back transaction shows fair value ₹20,07,00,000 and ₹10,145.66 a unit
- [x] 4.3 Write `features/fund/evergreen/nav_from_portfolio.feature` (H9, E18, E19, E20) and run it until green

## 5. Wrap-up

- [x] 5.1 Update design.md's Feature column to the three feature files above. Verify: each ID's Feature cell names the file that holds its scenario
- [x] 5.2 Coverage check: the set of H/E/X IDs in design.md equals the set of `# ID —` comments in the three features. Verify: a grep/compare prints no difference
- [x] 5.3 Run the four features plus `features/fund/evergreen/regression.feature` and `orders.feature`, and confirm everything is green
- [ ] 5.4 (QA) Manual check on a deployed build: subscribe with two KYCs, link a KYC with the picker, generate and approve a quarter's statements, read as the investor; record sign-off here
