class ImportExchangeRate < ImportUtil
  STANDARD_HEADERS = ["From", "To", "Rate", "Rate", "As Of", "Notes"].freeze

  # No custom fields for ExchangeRate
  step nil, delete: :create_custom_fields

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @exchange_rates = []
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug { "Processing exchange_rate #{user_data}" }
    exchange_rate_attributes = get_exchange_rate_attributes(user_data, import_upload)

    exchange_rate = ExchangeRate.find_by(exchange_rate_attributes.slice(:from, :to, :entity_id, :as_of))
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
      notes: user_data["Notes"]
    }
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
