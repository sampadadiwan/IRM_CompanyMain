class CapitalRemittancePaymentDestroy < CapitalRemittancePaymentAction
  step :destroy
  left :handle_errors, Output(:failure) => End(:failure)
end
