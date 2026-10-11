class ImportExchangeRate < ImportUtil
  # "Rate Type" and "Fund" are optional. Uploaded rates are always Manual (provider "Upload");
  # a Fund makes the rate fund-specific (only funds with "Use fund-specific FX rates").
  # Worked examples E15, X33, X34 — openspec/changes/fund-market-data/business-rules.md
  STANDARD_HEADERS = ["From", "To", "Rate", "As Of", "Notes"].freeze
  # Optional: older sheets without them still upload (validate_headers treats standard headers as required)
  OPTIONAL_HEADERS = ["Rate Type", "Fund"].freeze

  # No custom fields for ExchangeRate
  step nil, delete: :create_custom_fields

  def standard_headers
    STANDARD_HEADERS
  end

  def ignore_headers
    OPTIONAL_HEADERS
  end

  def initialize(**)
    super
    @exchange_rates = []
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug { "Processing exchange_rate #{user_data}" }
    exchange_rate_attributes = get_exchange_rate_attributes(user_data, import_upload)

    exchange_rate = ExchangeRate.find_by(exchange_rate_attributes.slice(:from, :to, :entity_id, :as_of, :source, :owner_type, :owner_id))
    if exchange_rate.present?
      raise "Duplicate - an exchange rate for #{exchange_rate_attributes[:from]} to #{exchange_rate_attributes[:to]} as of #{exchange_rate_attributes[:as_of]} already exists"
    else
      ExchangeRate.create!(exchange_rate_attributes)
      true
    end
  end

  def get_exchange_rate_attributes(user_data, import_upload)
    {
      from: cell(user_data, "From", required: true),
      to: cell(user_data, "To", required: true),
      import_upload_id: import_upload.id,
      rate: cell(user_data, "Rate", required: true),
      entity_id: import_upload.entity_id,
      as_of: parse_date_cell(user_data, "As Of", required: true),
      notes: user_data["Notes"],
      source: "manual",
      provider: "Upload",
      rate_type: user_data["Rate Type"].presence&.downcase || "reference"
    }.merge(owner_attributes(user_data, import_upload))
  end

  # X33/X34 — Error case: the Fund column must name a fund of this entity that uses its own rates
  def owner_attributes(user_data, import_upload)
    fund_name = user_data["Fund"].to_s.strip
    return { owner_type: nil, owner_id: nil } if fund_name.blank?

    fund = import_upload.entity.funds.find_by(name: fund_name)
    raise "Fund #{fund_name} not found" unless fund
    raise "Fund #{fund_name} does not use fund-specific FX rates" unless fund.features.use_own_fx_rates?
    # H21 — same rule as ExchangeRatePolicy#create?: a fund-specific rate needs update access on the fund
    raise "You do not have access to update fund #{fund_name}" unless import_upload.user && FundPolicy.new(import_upload.user, fund).update?

    { owner_type: "Fund", owner_id: fund.id }
  end

  def post_process(_ctx, import_upload:, **)
    super

    import_upload.imported_data.latest.each do |exchange_rate|
      # Ensure other dependent PIs get updated with this new exchange rate
      ExchangeRatePortfolioInvestmentJob.perform_now(exchange_rate.id)

      ExchangeRateCommitmentAdjustmentJob.perform_later(exchange_rate.id) if exchange_rate.entity.customization_flags.enable_exchange_rate_commitment_adjustment?
    end
    true
  end
end
