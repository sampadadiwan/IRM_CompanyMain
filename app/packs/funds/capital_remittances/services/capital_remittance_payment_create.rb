class CapitalRemittancePaymentCreate < CapitalRemittancePaymentAction
  step :set_amount
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
end
