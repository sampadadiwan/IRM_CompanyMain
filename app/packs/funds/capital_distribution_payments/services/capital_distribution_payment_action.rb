class CapitalDistributionPaymentAction < Trailblazer::Operation
  def setup_distribution_fees(_ctx, capital_distribution_payment:, **)
    capital_distribution_payment.setup_distribution_fees
    true
  end

  def set_investor_name(_ctx, capital_distribution_payment:, **)
    capital_distribution_payment.set_investor_name
  end

  def set_net_payable(_ctx, capital_distribution_payment:, **)
    capital_distribution_payment.set_net_payable if capital_distribution_payment.net_payable_cents_changed?
    true
  end

  def send_notification(_ctx, capital_distribution_payment:, **)
    if capital_distribution_payment.completed && !capital_distribution_payment.destroyed?
      Rails.logger.debug { "Sending notification for capital_distribution_payment #{capital_distribution_payment.id}" }
      capital_distribution_payment.send_notification
    else
      Rails.logger.debug { "Not sending notification for capital_distribution_payment #{capital_distribution_payment.id}" }
    end
    true
  end

  def save(_ctx, capital_distribution_payment:, **)
    capital_distribution_payment.save
  end

  def touch_investor_entity(_ctx, capital_distribution_payment:, **)
    capital_distribution_payment.update_investor_entity
  end

  def handle_errors(ctx, capital_distribution_payment:, **)
    unless capital_distribution_payment.valid?
      ctx[:errors] = capital_distribution_payment.errors.full_messages.join(", ")
      Rails.logger.error capital_distribution_payment.errors.full_messages
    end
    capital_distribution_payment.valid?
  end
end
