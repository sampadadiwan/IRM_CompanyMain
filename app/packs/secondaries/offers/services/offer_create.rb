class OfferCreate < OfferAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :validate_pan_card
  step :validate_bank
end
