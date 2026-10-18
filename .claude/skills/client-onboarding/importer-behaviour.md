# Import pipeline — verified behaviour

Each fact names its source. Re-verify before relying on one if the code may have changed.

## Entry point

- `ImportUpload` (`app/packs/misc/import_uploads/models/import_upload.rb`); `TYPES` lists the 38
  importable types. `ImportUploadsController#create` has a `format.json` branch, so an upload can
  be created over HTTP; `ImportUploadJob` processes it.
- Templates: `public/sample_uploads/`.
- Row-level results are a file (`import_upload.import_results_data`), not DB rows; counts are in
  `total_rows_count`, `processed_row_count`, `failed_row_count`.

## Extra columns → custom fields (`ImportUtil#create_custom_fields`, import_util.rb:61)

- Extra headers = `headers - standard_headers - ignore_headers` (import_util.rb:156).
- **Single-form-type imports** (Investor, CapitalCall, CapitalRemittance, …): after rows import,
  `FormType.save_cf_from_import` (form_type.rb:36) creates any missing field — always as
  **`TextField`**, labelled with the raw header. Dates/numbers become text.
- **`FormType::MULTIPLE_FORM_TYPES_ALLOWED`** (CapitalCommitment, InvestorKyc, IndividualKyc,
  NonIndividualKyc, Offer, Interest, SupportAgent): **no** field is auto-created.
- ⇒ The agent creates typed fields first via the `FormCustomField` import type.

## No dry run

- Importers have no validate-only mode. "Check" means validating the generated file against the
  template's columns and rules before upload. (Logged in api-gaps.md.)

## Undo

- `ImportUploadDeleteAllJob` destroys `import_upload.imported_data` one by one under
  `Audited.audit_class.as_user(user)`, then zeroes the counts. Per-upload, via app code.

## Sandbox (`ApplicationMailer`)

- `@to = sandbox ? sandbox_emails : user.email` (application_mailer.rb:100); helpers
  `sandbox_email`, `sandbox_whatsapp_numbers` (lines 151–156). About 20 other files reference
  sandbox individually — verify each notifier an import can trigger honours it.

## Real-world failure rates (production copy, 2026-10-18)

| Client | Type | Uploads | Rows | Failed |
|---|---|---|---|---|
| Ambit 7442 | InvestorKyc | 64 | 74 | 35 |
| Ambit 7442 | CapitalCommitment | 52 | 56 | 27 |
| Fireside 5632 | CapitalRemittance | 28 | 30,003 | 8,115 |
| Fireside 5632 | CapitalDistribution | 7 | 2,175 | 2,039 |

Ops today retry almost row by row. The agent's main value is getting files right before upload
and turning failed rows into concrete fixes. Ambit's actual order: InvestorKyc → FormCustomField →
Investor → CapitalCommitment → DealInvestor → InvestorAccess (last, 3 months later).
