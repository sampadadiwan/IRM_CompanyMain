class CapitalDistributionPaymentCreate < CapitalDistributionPaymentAction
  step :set_investor_name
  step :set_net_payable
  step :setup_distribution_fees
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :send_notification
  step :touch_investor_entity
end
