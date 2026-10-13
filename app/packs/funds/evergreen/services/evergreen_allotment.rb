# Allots units for paid, confirmed subscriptions and cancels exact units for paid redemptions, then
# sends the contract note / redemption advice (design card ⑦). Called by DealingSettlementSyncJob for
# every change to a dealing date's settlement record; idempotent (a fill with units moved is skipped).
# Worked examples H21, H23, H24, H25, E32 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenAllotment
  def self.sync(record_type, record_id, user_id = nil)
    case record_type
    when "CapitalRemittance" then sync_remittance(CapitalRemittance.find_by(id: record_id), user_id)
    when "CapitalDistributionPayment" then sync_payment(CapitalDistributionPayment.find_by(id: record_id), user_id)
    end
  end

  def self.sync_remittance(remittance, user_id)
    return unless remittance

    fill = DealingFill.find_by(capital_remittance_id: remittance.id)
    # Before confirmation the money just moves the order's journey on (pre-funded)
    DealingOrder.where(capital_remittance_id: remittance.id).find_each do |order|
      order.journey_progress!
      # Money recorded and verified → "Payment received" to the investor, once (§ Notifications)
      EvergreenAlerts.payment_verified(order) if remittance.verified
    end
    # Only once the whole subscription is in (same 10-paise tolerance as DealingOrder#fully_paid?):
    # a part payment must not allot part of the units and strand the rest (review finding)
    fully_paid = remittance.collected_amount_cents.to_d >= remittance.call_amount_cents.to_d - 10
    allot(fill, user_id) if fill && remittance.verified && fully_paid && fill.dealing_date.settled_or_closed?
  end

  def self.sync_payment(payment, user_id)
    return unless payment&.completed

    fill = DealingFill.find_by(capital_distribution_payment_id: payment.id)
    cancel(fill, user_id) if fill
  end

  # Subscription: the existing engine allots amount ÷ NAV per unit (unit prices set at confirm)
  def self.allot(fill, user_id)
    unit = nil
    fill.with_lock do
      next if fill.fund_unit_id # a retry: settled below still sends the email if it was missed

      unit, errors = DefaultUnitAllocationEngine.new.allocate_remittance(fill.capital_remittance, "Allotted on dealing date #{fill.dealing_date.date}")
      return alert(user_id, "Units not allotted for #{fill.dealing_order.investor.investor_name}: #{Array(errors).join(', ')}") unless unit&.persisted?

      fill.update!(fund_unit_id: unit.id)
    end
    # Email now (no template) or leave for Generate documents → Approve & send
    EvergreenDealingDocuments.settled(fill)
  end

  # Redemption: exact units through the engine's dealing path
  def self.cancel(fill, user_id)
    fill.with_lock do
      next if fill.fund_unit_id # a retry: settled below still sends the email if it was missed

      unit, errors = DefaultUnitAllocationEngine.new.allocate_dealing_redemption(fill.capital_distribution_payment, fill, "Redeemed on dealing date #{fill.dealing_date.date}")
      return alert(user_id, "Units not cancelled for #{fill.dealing_order.investor.investor_name}: #{Array(errors).join(', ')}") unless unit&.persisted?

      fill.update!(fund_unit_id: unit.id)
    end
    EvergreenDealingDocuments.settled(fill)
  end

  def self.alert(user_id, message)
    Rails.logger.error("[EvergreenAllotment] #{message}")
    UserAlert.new(user_id:, message:, level: :danger).broadcast if user_id
    nil
  end
end
