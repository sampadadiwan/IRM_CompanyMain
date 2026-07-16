class CapitalDistributionPaymentUpdate < CapitalDistributionPaymentAction
  step :set_investor_name
  step :setup_distribution_fees
  step :set_net_payable
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :touch_investor_entity
end
