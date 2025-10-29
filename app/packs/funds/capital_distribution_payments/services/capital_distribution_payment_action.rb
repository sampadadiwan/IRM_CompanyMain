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

  def send_notification(ctx, capital_distribution_payment:, **)
    msg = capital_distribution_payment.send_notification(force: ctx[:force_notification])
    ctx[:notification_message] = msg || "Notification sent successfully."

    capital_distribution_payment.notification_sent
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
