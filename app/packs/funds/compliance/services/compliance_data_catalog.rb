# ③ The only allowlist of record types and fields a pack may measure (Security item 4/5).
# A pack's definition names a source + field; nothing in a definition is ever evaluated or
# constantized — the model classes and SQL fragments below are fixed in code.
# `account_entries` is deliberately not a source (CLAUDE.md large-table rules).
# Worked examples H2, E4, X5 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceDataCatalog
  class UnknownSource < StandardError; end
  class UnknownField < StandardError; end

  # model:   class name (fixed here, resolved via SOURCE_MODELS below)
  # date:    column compared with the run's as-of date (nil = no date filter)
  # record_date: the column a record-level check compares document dates with
  # fields:  field name → SQL expression (money in major units: _cents / 100.0)
  # groups:  group name → column
  # json_fields: true when `json_fields.<custom field>` is allowed
  Source = Struct.new(:name, :model_name, :date, :record_date, :fields, :groups, :json_fields, :label_for, keyword_init: true)

  SOURCES = {
    "commitments" => Source.new(
      name: "commitments", model_name: "CapitalCommitment", date: "commitment_date", record_date: "commitment_date",
      fields: { "amount" => "capital_commitments.committed_amount_cents / 100.0", "investor" => "capital_commitments.investor_id",
                "id" => "capital_commitments.id" },
      groups: { "investor" => "capital_commitments.investor_id" }, json_fields: true, label_for: { "investor" => :investor }
    ),
    "payments" => Source.new(
      name: "payments", model_name: "CapitalRemittancePayment", date: "payment_date", record_date: "payment_date",
      fields: { "amount" => "capital_remittance_payments.amount_cents / 100.0", "investor" => "capital_remittance_payments.investor_id" },
      groups: { "investor" => "capital_remittance_payments.investor_id" }, json_fields: false, label_for: { "investor" => :investor }
    ),
    "distributions" => Source.new(
      name: "distributions", model_name: "CapitalDistribution", date: "distribution_date", record_date: "distribution_date",
      fields: { "amount" => "capital_distributions.distribution_amount_cents / 100.0" },
      groups: {}, json_fields: true, label_for: {}
    ),
    "portfolio_investments" => Source.new(
      name: "portfolio_investments", model_name: "PortfolioInvestment", date: "investment_date", record_date: "investment_date",
      fields: { "cost" => "portfolio_investments.amount_cents / 100.0", "quantity" => "portfolio_investments.quantity",
                "sector" => "portfolio_investments.sector", "transaction" => "portfolio_investments.quantity",
                "investee" => "portfolio_investments.portfolio_company_id", "id" => "portfolio_investments.id" },
      groups: { "investee" => "portfolio_investments.portfolio_company_id", "sector" => "portfolio_investments.sector" },
      json_fields: true, label_for: { "investee" => :investor }
    ),
    "investor_kycs" => Source.new(
      name: "investor_kycs", model_name: "InvestorKyc", date: nil, record_date: "created_at",
      fields: { "investor" => "investor_kycs.investor_id", "id" => "investor_kycs.id" },
      groups: { "investor" => "investor_kycs.investor_id" }, json_fields: true, label_for: { "investor" => :investor }
    )
  }.freeze

  # Fixed class lookup — never from user input
  SOURCE_MODELS = {
    "CapitalCommitment" => -> { CapitalCommitment }, "CapitalRemittancePayment" => -> { CapitalRemittancePayment },
    "CapitalDistribution" => -> { CapitalDistribution }, "PortfolioInvestment" => -> { PortfolioInvestment },
    "InvestorKyc" => -> { InvestorKyc }
  }.freeze

  # Filters a definition may use besides plain fields
  SPECIAL_FILTERS = %w[investor_group transaction].freeze
  FILTER_OPS = %w[eq ne gt gte lt lte in not_in].freeze
  JSON_FIELD = /\Ajson_fields\.([a-z0-9_]{1,60})\z/

  def self.source(name)
    SOURCES[name.to_s] || raise(UnknownSource, "Unknown source: #{name}")
  end

  def self.model(source_name)
    SOURCE_MODELS.fetch(source(source_name).model_name).call
  end

  def self.source?(name)
    SOURCES.key?(name.to_s)
  end

  # E4: custom fields are allowed as `json_fields.<name>` on sources that carry json_fields
  def self.field?(source_name, field)
    src = SOURCES[source_name.to_s]
    return false unless src

    src.fields.key?(field.to_s) || (src.json_fields && JSON_FIELD.match?(field.to_s))
  end

  def self.group?(source_name, group)
    SOURCES[source_name.to_s]&.groups&.key?(group.to_s) || false
  end

  # SQL for a field — only ever from the frozen hash above or a regex-checked custom field name
  def self.field_sql(source_name, field)
    src = source(source_name)
    return src.fields[field.to_s] if src.fields.key?(field.to_s)

    m = JSON_FIELD.match(field.to_s)
    raise UnknownField, "Unknown field: #{field}" unless m && src.json_fields

    "JSON_EXTRACT(#{model(source_name).table_name}.json_fields, '$.#{m[1]}')"
  end
end
