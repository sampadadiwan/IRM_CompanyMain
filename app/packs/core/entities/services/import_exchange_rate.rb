class ImportExchangeRate < ImportUtil
  STANDARD_HEADERS = ["From", "To", "Rate", "Rate", "As Of", "Notes"].freeze

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
      ret_val = [false, "Duplicate, already present"]
    else
      exchange_rate = ExchangeRate.create(exchange_rate_attributes)
      ret_val = if exchange_rate.valid?
                  [true, "Success"]
                else
                  [false, exchange_rate.errors.full_messages]
                end
    end
    ret_val
  end

  def get_exchange_rate_attributes(user_data, import_upload)
    {
      from: user_data["From"],
      to: user_data["To"],
      import_upload_id: import_upload.id,
      rate: user_data["Rate"],
      entity_id: import_upload.entity_id,
      as_of: Date.parse(user_data["As Of"]),
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
