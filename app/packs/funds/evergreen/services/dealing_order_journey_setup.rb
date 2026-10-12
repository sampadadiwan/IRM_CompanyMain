# The order journey (US-14): one template covering both kinds — subscription-only and
# redemption-only steps are skipped by kind, and "Collect subscription money" by payment timing.
# Seeded per entity by EvergreenEnable; its catch-all rule launches it on every new order, and
# DealingOrder#skip_journey? keeps out funds (or kinds) with order journeys off.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingOrderJourneySetup < JourneySetup
  WORKFLOWABLE_TYPE = "DealingOrder".freeze
  KEY_PREFIX = "dealing_order.".freeze
  LABEL = "evergreen order journey".freeze
  RECORD = "order".freeze
  FULL_KEY = "dealing_order".freeze
  FULL_NAME = "Evergreen Order".freeze
  FULL_LABEL = "Evergreen Order".freeze
  SIGN_OFF_NAME = nil
  DESCRIPTION = "Checks each evergreen subscription or redemption before it is dealt. Seeded by CapHive; " \
                "admins can remove steps or make them optional.".freeze

  # [name, kind, check, skip, unlocks, description]
  FULL_STEPS = [
    ["Check investor KYC", "system", "check_investor_kyc", "not_subscription", nil,
     "The investor's KYC for this fund is approved."],
    ["Collect signed subscription form", "system", "collect_signed_form", "not_subscription", nil,
     "A signed subscription form is attached to the order."],
    ["Verify request", "system", "verify_request", "not_redemption", nil,
     "The request is from an authorised signatory."],
    ["Accept order", "system", "accept_order", nil, nil,
     "A GP approver has accepted the order."],
    ["Collect subscription money", "system", "collect_money", "money_not_needed", nil,
     "Payment is recorded and verified for the full amount (funds paid before dealing)."],
    ["Ready to deal", "system", "ready_to_deal", nil, nil,
     "Every earlier step is done or not applicable, so the order is priced on its dealing date."],
    ["Allot units and send contract note", "system", "allotted", "not_subscription", nil,
     "Units are allotted at the dealing date's NAV and the contract note is sent."],
    ["Pay redemption", "system", "paid", "not_redemption", nil,
     "The redemption payment is marked paid."],
    ["Cancel units and send redemption advice", "system", "cancelled", "not_redemption", nil,
     "The redeemed units are cancelled and the redemption advice is sent."]
  ].freeze
  PRE_DEAL_CHECKS = %w[check_investor_kyc collect_signed_form verify_request accept_order collect_money].freeze
end
