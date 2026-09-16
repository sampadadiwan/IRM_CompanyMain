# CustomFieldsProxy: Replacing OpenStruct for Custom Fields

## Background

The codebase previously used `OpenStruct` in two distinct ways:

1. **Custom field access** — `WithCustomField#custom_fields` returned `OpenStruct.new(json_fields)` to give callers attribute-style access (e.g. `record.custom_fields.nationality`).
2. **Ad-hoc value objects** — service objects and generators built anonymous `OpenStruct.new(key: value, ...)` structs to pass shaped data to template decorators and Sablon Word templates.

Both patterns had performance problems at scale.

## The Problem with OpenStruct

`OpenStruct.new(hash)` defines a getter and setter method on the **instance's singleton class** for every key in the hash. This has two costs:

- **Memory**: Each singleton class holds its own method table. With 200+ custom fields per KYC record, a list page that loads 50 records creates 10,000+ singleton-class method definitions.
- **Dispatch slowdown**: Ruby's method lookup cache is invalidated globally each time a new method is defined anywhere. Thousands of OpenStruct definitions per request degrade method dispatch across the entire application.

These definitions also **linger in memory** for the lifetime of the Ruby process — they are never garbage-collected because singleton classes are anchored to their object, and in practice many OpenStruct objects are cached or referenced from view contexts.

## Solution 1: CustomFieldsProxy (for custom fields)

Custom field keys come from `form_custom_fields` at runtime and vary per entity, so `Struct` and `Data.define` are not usable (both require keys to be fixed at class-definition time, and a dynamically created `Struct.new(*keys)` would allocate a new anonymous class per record — worse than OpenStruct).

`CustomFieldsProxy` uses `method_missing` instead, so **no methods are defined** and no singleton class is allocated:

```ruby
class CustomFieldsProxy
  def initialize(hash)
    @hash = hash || {}
  end

  def [](key)        = @hash[key.to_s]           # :symbol and "string" both work
  def present?       = @hash.present?
  def blank?         = @hash.blank?
  def respond_to_missing?(name, _) = @hash.key?(name.to_s) || super
  def method_missing(name, *) = @hash[name.to_s]  # returns nil for unknown keys
end
```

### Access patterns supported

| Pattern | Used in |
|---|---|
| `.field_name` | Mailers, jobs, doc generators |
| `.send(variable)` | `capital_commitment_shared`, `portfolio_computations` |
| `[:symbol_key]` | `fund_formula`, `run_formulas` |
| `["string_key"]` | `generate_aml_report_job` |
| `.present?` / `.blank?` | `secondary_sales`, offer jobs |

Unknown keys return `nil` (matching OpenStruct behaviour), so callers using `&.` or `.present?` guards continue to work without change.

### Where it is used

- `WithCustomField#custom_fields` — the main concern used by all AR models with JSON custom fields
- `WithCustomField#custom_fields_with_td` — decorated variant for template rendering
- `ApplicationRecordSqlite#custom_fields` — SQLite models used by the allocation engine
- `FormTypeHelper#custom_form_fields` — form rendering (`model.properties` aliases `json_fields`)

## Solution 2: Typed value objects (for ad-hoc structs)

Where the set of keys **is** known at definition time (service return values, amounts passed to Sablon templates), `OpenStruct` was replaced with either:

- **`Data.define`** — for immutable, read-only value objects (amounts, fund units, fee entries).
- **`Struct.new`** — when the object needs to be mutated after construction (e.g. accumulating totals with `+=`).

Both are defined as named inner classes so they are self-documenting and stable across requests. A plain `Struct.new` also includes `success?` when the struct models a result type:

```ruby
KycUpsertResult = Struct.new(:success, :investor_kyc, :errors) do
  def success? = success
end
```

### Replacements made in this changeset

| File | Old | New |
|---|---|---|
| `digio_esign_helper.rb` | `OpenStruct.new(success:, errors:, message:)` | `DigioResult` (Struct) |
| `investor_kyc_upserter.rb` | `OpenStruct.new(success?:, investor_kyc:, errors:)` | `KycUpsertResult` (Struct) |
| `kyc_doc_generator.rb` | `OpenStruct.new({committed_amount: ...})` | `KycAmounts` (Data.define) |
| `kyc_doc_generator.rb` | `OpenStruct.new({current:, before_end_date:, between_dates:})` | `KycFundUnitsContext` (Data.define) |
| `kyc_doc_generator.rb` | `OpenStruct.new(unit_type:, ...)` per fund_unit | `AggregatedFundUnit` (mutable Struct) |
| `soa_generator.rb` | Multiple `OpenStruct.new(...)` for amounts/fund_units | `CommittedAmounts`, `RemittanceAmounts`, `RemittancePaymentsAmounts`, `DistributionAmounts`, `SoaFundUnits` (all Data.define) |
| `capital_distribution_payment.rb` | `OpenStruct.new(name:, date:, amount:, fee_type:)` | `FeeEntry` (Data.define), `ConsolidatedFee` (Struct — mutable, `total_amount_across_folios` annotated post-construction) |
| `capital_remittance.rb` | `OpenStruct.new(name:, date:, amount:)` | `FeeEntry` (Data.define), `ConsolidatedFee` (Struct — mutable, `total_amount_across_folios` annotated post-construction) |
| `fund_doc_generator.rb` | `OpenStruct.new({committed_amount: ...})` | `FundAmounts` (Data.define) |
| `account_entry_pivot.rb` | `OpenStruct.new(amount:, reporting_date:, ...)` | `PivotEntry` (mutable Struct) |

## Downstream compatibility fixes

- **`DocGenContext`** (`doc_gen_context.rb`): Added `Data` to the container-type check alongside `OpenStruct` and `Struct`, so `Data.define` instances are correctly traversed during template variable extraction.
- **`FundFormula#skip_statement`**: Updated to also short-circuit on `CustomFieldsProxy` instances, preventing formula evaluation from trying to iterate over proxy objects.
- **`KycDocGenerator#portfolio_company_cumulative_folio_entries`**: Now returns `[]` (empty array) instead of `OpenStruct.new` when `fund_id` is blank — the result feeds `decorate_collection`, which expects an array.

## Guidelines for new code

- **Custom field access** — always go through `record.custom_fields` (returns `CustomFieldsProxy`). Never call `OpenStruct.new(json_fields)` directly.
- **New value objects with fixed keys** — use `Data.define` for immutable, `Struct.new` for mutable. Define them as named inner constants, not inline anonymous structs.
- **Dynamic-key structs** — use `CustomFieldsProxy.new(hash)` when keys are not known until runtime.
- **Do not introduce new `OpenStruct` usage** — Rubocop's `Style/OpenStructUse` cop is enabled in this codebase to enforce this.
