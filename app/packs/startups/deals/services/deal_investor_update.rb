class DealInvestorUpdate < DealInvestorAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :grant_access_to_deal
end
