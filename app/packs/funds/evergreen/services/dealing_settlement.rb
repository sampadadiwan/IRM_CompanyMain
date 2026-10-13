# Drives CapHive's existing settlement records for a dealing date through their existing services
# (design card ⑥). Evergreen users only ever see these as "Subscription settlement" /
# "Redemption settlement". Created approved with every closed-ended notice flag off, and with no
# journey (CapitalCall#skip_journey?) — the dealing date's own journey replaces it.
# Worked examples H7, H21, H22 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingSettlement
  class Error < StandardError; end

  # The subscription settlement (CapitalCall, call basis Upload) for a dealing date, created once
  # under a lock on the dealing date so two first orders can't create two.
  def self.subscription_call(dealing_date, user)
    return dealing_date.subscription_call if dealing_date.subscription_call

    dealing_date.with_lock do
      return dealing_date.subscription_call if dealing_date.reload.subscription_call

      fund = dealing_date.fund
      call = CapitalCall.new(
        entity_id: fund.entity_id, fund:, name: EvergreenLabels.settlement_name(:subscription, dealing_date.date),
        call_basis: "Upload", call_date: dealing_date.date, due_date: dealing_date.date, percentage_called: 0,
        approved: true, approved_by_user: user, send_call_notice_flag: false, send_payment_notification_flag: false,
        generate_remittances: false, manual_generation: true
      )
      call.evergreen_settlement_flag = true
      result = CapitalCallCreate.call(capital_call: call)
      raise Error, result[:errors].presence || call.errors.full_messages.to_sentence unless result.success?

      dealing_date.update!(subscription_call: call)
      call
    end
  end

  # One subscription payment (CapitalRemittance) per subscription order, for its amount, no fees.
  # Idempotent: returns the order's existing one.
  def self.ensure_subscription_payment(order, user)
    return order.capital_remittance if order.capital_remittance

    call = subscription_call(order.dealing_date, user)
    folio = order.capital_commitment.reload
    remittance = CapitalRemittance.new(
      entity_id: folio.entity_id, fund_id: folio.fund_id, capital_call: call, capital_commitment: folio,
      investor_id: folio.investor_id, folio_id: folio.folio_id, created_by: "Evergreen",
      folio_call_amount_cents: order.amount_cents, call_amount_cents: order.amount_cents,
      remittance_date: order.dealing_date.date, verified: false
    )
    result = CapitalRemittanceCreate.call(capital_remittance: remittance)
    raise Error, result[:errors].presence || remittance.errors.full_messages.to_sentence unless result.success?

    order.update!(capital_remittance: remittance)
    remittance
  end

  # Remove an order's unpaid subscription payment (cancel / roll)
  def self.remove_subscription_payment(order)
    rem = order.capital_remittance
    return true unless rem
    return false if rem.capital_remittance_payments.exists?

    order.update!(capital_remittance: nil)
    rem.destroy
    true
  end

  FEE_ENTRY_NAME = "Early Redemption Fee".freeze

  # Confirm-time settlement (inside DealingConfirm's transaction): unit prices on the subscription
  # settlement, pay-after folios and payment rows, and the redemption settlement with one payment per
  # filled redemption and its early-redemption fee.
  # Worked examples H21, H22, E31, E32
  def self.settle(dealing_date, user)
    fills = dealing_date.dealing_fills.includes(dealing_order: %i[capital_commitment capital_remittance]).to_a
    settle_subscriptions(dealing_date, fills.select(&:subscription?), user)
    settle_redemptions(dealing_date, fills.select { |f| f.redemption? && f.units.positive? }, user)
    true
  end

  def self.settle_subscriptions(dealing_date, fills, user)
    return if fills.empty?

    call = subscription_call(dealing_date, user)
    prices = fills.group_by(&:unit_type).transform_values do |fs|
      { "price" => (fs.first.nav_per_unit_cents.to_d / 100).to_s("F"), "premium" => "0" }
    end
    call.update!(unit_prices: (call.unit_prices || {}).merge(prices))
    fills.each do |fill|
      order = fill.dealing_order
      # Pay after dealing: the folio and its payment row are created now (H22)
      unless order.capital_remittance
        FolioOpener.call(order, user)
        ensure_subscription_payment(order.reload, user)
      end
      fill.update!(capital_remittance_id: order.reload.capital_remittance_id)
    end
  end

  def self.settle_redemptions(dealing_date, fills, user)
    return if fills.empty?

    dist = redemption_distribution(dealing_date, fills, user)
    due = payment_due_date(dealing_date)
    fills.each do |fill|
      record_early_fee(dist, fill) if fill.early_fee_cents.positive?
      folio = fill.dealing_order.capital_commitment
      payment = CapitalDistributionPayment.new(
        entity_id: folio.entity_id, fund_id: folio.fund_id, capital_distribution: dist, capital_commitment: folio,
        # Net of this fill's own early-redemption fee, so two redemptions on one folio never share a fee
        investor_id: folio.investor_id, folio_id: folio.folio_id, cost_of_investment_cents: fill.amount_cents - fill.early_fee_cents.to_d,
        income_cents: 0, reinvestment_cents: 0, payment_date: due, completed: false
      )
      result = CapitalDistributionPaymentCreate.call(capital_distribution_payment: payment)
      raise Error, result[:errors].presence || payment.errors.full_messages.to_sentence unless result.success?

      fill.update!(capital_distribution_payment_id: payment.id)
    end
  end

  # The redemption settlement (CapitalDistribution, Upload, no generated payments, every notice off)
  def self.redemption_distribution(dealing_date, fills, user)
    return dealing_date.redemption_distribution if dealing_date.redemption_distribution

    fund = dealing_date.fund
    dist = CapitalDistribution.new(
      entity_id: fund.entity_id, fund:, title: EvergreenLabels.settlement_name(:redemption, dealing_date.date),
      distribution_date: dealing_date.date, distribution_on: "Upload", generate_payments: false, approved: true,
      approved_by_user: user, send_notification_on_complete: false, manual_generation: true,
      unit_prices: fills.group_by(&:unit_type).transform_values { |fs| (fs.first.nav_per_unit_cents.to_d / 100).to_s("F") }
    )
    dist.evergreen_settlement_flag = true
    result = CapitalDistributionCreate.call(capital_distribution: dist)
    raise Error, dist.errors.full_messages.to_sentence.presence || "Could not create the redemption settlement" unless result.success?

    dealing_date.update!(redemption_distribution: dist)
    dist
  end

  # Early-redemption fee: a folio ledger entry for the accounts. The payment itself is created net of
  # the fee (settle_redemptions), so units cancelled stay exact and the fee is deducted once per fill
  # (E32; review finding: a shared distribution-level fee was deducted from every payment of the folio)
  def self.record_early_fee(dist, fill)
    folio = fill.dealing_order.capital_commitment
    AccountEntry.create!(entity_id: folio.entity_id, fund_id: folio.fund_id, capital_commitment: folio, investor_id: folio.investor_id,
                         folio_id: folio.folio_id, name: FEE_ENTRY_NAME, entry_type: "Expense", reporting_date: dist.distribution_date,
                         period: "As of Date", amount_cents: fill.early_fee_cents, parent_type: "DealingFill", parent_id: fill.id, generated: true)
  end

  # Dealing date + N business days (Monday–Friday)
  def self.payment_due_date(dealing_date)
    days = dealing_date.fund.evergreen_fund_setting.redemption_settlement_days
    date = dealing_date.date
    while days.positive?
      date += 1.day
      days -= 1 unless date.saturday? || date.sunday?
    end
    date
  end

  # Undo (nothing settled yet): remove the redemption settlement, the fees, pay-after payment rows
  # and folios, and the unit prices; pre-funded payment rows stay with their orders.
  # Worked example E33
  def self.unsettle(dealing_date, user)
    dealing_date.dealing_fills.includes(:dealing_order).find_each do |fill|
      AccountEntry.where(fund_id: fill.fund_id, parent_type: "DealingFill", parent_id: fill.id).delete_all
      next unless fill.subscription? && !dealing_date.pre_funded?

      order = fill.dealing_order
      remove_subscription_payment(order)
      FolioOpener.reverse(order, user)
    end
    if (dist = dealing_date.redemption_distribution)
      dealing_date.update!(redemption_distribution: nil)
      dist.evergreen_settlement_flag = true
      raise Error, "Could not remove the redemption settlement" unless CapitalDistributionDestroy.call(capital_distribution: dist).success?
    end
    dealing_date.subscription_call&.update!(unit_prices: {})
    true
  end
end
