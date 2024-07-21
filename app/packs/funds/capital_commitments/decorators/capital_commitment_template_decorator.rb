class CapitalCommitmentTemplateDecorator < TemplateDecorator
  COMMITMENT_METHODS_START_WITH = %w[quarterly_ ytd_ since_inception_ as_on_date_ change_in_period_ change_in_ytd_].freeze

  def method_missing(method_name, *args, &)
    # This is typically used for the capital_commitment
    # Ex capital_commitment.quarterly_setup_fees
    if method_name.to_s.starts_with?("period_")
      attr_name = method_name.to_s.gsub("period_", "")
      amount_cents = quarterly(attr_name.humanize.titleize, nil, start_date, end_date)
      Money.new(amount_cents, currency)
    # Ex capital_commitment.ytd_setup_fees
    elsif method_name.to_s.starts_with?("ytd_")
      attr_name = method_name.to_s.gsub("ytd_", "")
      amount_cents = year_to_date(attr_name.humanize.titleize, nil, start_date, end_date)
      Money.new(amount_cents, currency)
    # Ex capital_commitment.since_inception_setup_fees
    elsif method_name.to_s.starts_with?("since_inception_")
      attr_name = method_name.to_s.gsub("since_inception_", "")
      amount_cents = since_inception(attr_name.humanize.titleize, nil, start_date, end_date)
      Money.new(amount_cents, currency)
    elsif method_name.to_s.starts_with?("as_on_date_")
      attr_name = method_name.to_s.gsub("as_on_date_", "")
      amount_cents = on_date(attr_name.humanize.titleize, nil, end_date)
      Money.new(amount_cents, currency)
    elsif method_name.to_s.starts_with?("change_in_period_")
      attr_name = method_name.to_s.gsub("change_in_period_", "")
      amount_cents_start_date = on_date(attr_name.humanize.titleize, nil, start_date)
      amount_cents_end_date = on_date(attr_name.humanize.titleize, nil, end_date)
      Money.new(amount_cents_end_date - amount_cents_start_date, currency)
    elsif method_name.to_s.starts_with?("change_in_ytd_")
      attr_name = method_name.to_s.gsub("change_in_ytd_", "")
      amount_cents_start_date = on_date(attr_name.humanize.titleize, nil, start_of_financial_year_date(end_date))
      amount_cents_end_date = on_date(attr_name.humanize.titleize, nil, end_date)
      Money.new(amount_cents_end_date - amount_cents_start_date, currency)
    else
      super
    end
  rescue StandardError => e
    msg = "Error in CapitalCommitmentTemplateDecorator #{method_name}: #{e.message}"
    Rails.logger.error { msg }
    raise msg
  end

  def respond_to_missing?(method_name, include_private = false)
    COMMITMENT_METHODS_START_WITH.any? { |prefix| method_name.to_s.starts_with?(prefix) } || super
  end
end
