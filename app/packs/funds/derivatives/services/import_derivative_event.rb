# Upload of counterparty / administrator valuations for OTC contracts. One row per contract and
# date: Contract (name), Valuation Date, Value (signed, contract currency), Valued By, Delta (optional).
# Rows are recorded as valuation events through DerivativeEventRecorder (re-uploading the same row
# is harmless). Worked examples H14, E66 — openspec/changes/fund-market-data/business-rules.md
class ImportDerivativeEvent < ImportUtil
  STANDARD_HEADERS = ["Contract", "Valuation Date", "Value", "Valued By"].freeze
  OPTIONAL_HEADERS = ["Delta"].freeze

  # No custom fields on derivative events
  step nil, delete: :create_custom_fields

  def standard_headers
    STANDARD_HEADERS
  end

  def ignore_headers
    OPTIONAL_HEADERS
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    name = cell(user_data, "Contract", required: true).to_s.strip
    date = parse_date_cell(user_data, "Valuation Date", required: true)
    value = BigDecimal(cell(user_data, "Value", required: true).to_s.delete(","))
    scope = DerivativeContract.where(entity_id: import_upload.entity_id, name:)
    scope = scope.where(fund_id: import_upload.owner_id) if import_upload.owner_type == "Fund"
    contract = scope.first
    raise "Contract #{name} not found" unless contract

    result = DerivativeEventRecorder.call(contract:, idempotency_key: "upload:#{contract.id}:#{date.iso8601}:#{(value * 100).to_i}",
                                          params: { event_type: "valuation", event_date: date, value_cents: value * 100,
                                                    delta: user_data["Delta"].presence, source: "upload",
                                                    provider: user_data["Valued By"].to_s.strip.presence, import_upload_id: import_upload.id })
    raise result.errors.to_sentence unless result.success?

    true
  end
end
