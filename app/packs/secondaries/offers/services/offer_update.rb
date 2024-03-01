class OfferUpdate < OfferAction
  step :save
  left :handle_errors
  step :validate_pan_card
  step :validate_bank
end
