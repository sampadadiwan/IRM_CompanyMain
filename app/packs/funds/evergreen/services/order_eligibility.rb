# Validates an order before it is accepted. First failure wins, in the design's order (card ②).
# Messages are the proposal's Behavior Rules verbatim. Records the soft lock-up fee on the order.
# Worked examples H7, H9, E13, E16, X10–X15 — openspec/changes/open-ended-funds/design.md#worked-examples
class OrderEligibility
  def self.errors_for(order)
    new(order).errors
  end

  def initialize(order)
    @order = order
    @fund = order.fund
    @setting = @fund.evergreen_fund_setting
  end

  def errors
    check = %i[check_currency check_class check_kyc check_subscription check_form check_free_units check_lock_up check_min_holding]
    check.each do |m|
      msg = send(m)
      return [msg] if msg
    end
    []
  rescue DealingOrder::NoNav => e
    [e.message]
  end

  private

  attr_reader :order, :fund, :setting

  def term
    @term ||= setting.terms_for(order.unit_type)
  end

  def money(cents)
    EvergreenOrderMessages.money(cents, fund)
  end

  # The fund's evergreen wording ("units" / "shares", "folio" / "account") — EvergreenLabels
  def label(key)
    EvergreenLabels.t(key, fund:)
  end

  # 1. Worked example X11
  def check_currency
    folio = order.capital_commitment
    return nil if folio.nil? || folio.folio_currency.blank? || folio.folio_currency == fund.currency

    "Evergreen orders must be in the fund currency (#{fund.currency})"
  end

  # 2.
  def check_class
    return "#{order.unit_type} is not a unit class of this fund" unless fund.unit_types_list.include?(order.unit_type)
    return "Class #{order.unit_type} has no initial price yet" if term.initial_price_cents.blank?

    nil
  end

  # 2a. Every evergreen folio carries an approved KYC, and the order records it so a folio it opens
  # (now or at confirm) takes it. Sets order.investor_kyc_id as a side effect, like check_lock_up's fee.
  # evergreen-folio-soa ①: H1 single approved KYC used; H2 / E2 several → the pick; H3 / E5 a folio's
  # KYC is copied; X1 none approved; X2 several and none picked; X3 a KYC not among them; X4 folio without one
  def check_kyc
    folio = order.capital_commitment
    if folio
      # X4: a folio opened before KYCs were linked can't trade until one is linked on the folio page
      return "#{label(:capital_commitment)} #{folio.folio_id} has no approved KYC linked — link one on the #{EvergreenLabels.lower(label(:capital_commitment))} before placing orders." if folio.investor_kyc_id.nil?

      # H3 / E5: top-ups and redemptions are for the folio's own investing entity
      order.investor_kyc_id = folio.investor_kyc_id
      return nil
    end
    # A redemption without a folio is refused by check_free_units
    return nil unless order.subscription?

    approved = InvestorKyc.where(entity_id: order.entity_id, investor_id: order.investor_id, verified: true).order(:id).pluck(:id)
    # X1
    return "#{order.investor&.investor_name} has no approved KYC — it must be approved before subscribing." if approved.empty?
    # X3: only the investor's own approved KYCs (a portal user can post any id)
    return "Choose one of #{order.investor&.investor_name}'s approved investing entities." if order.investor_kyc_id.present? && approved.exclude?(order.investor_kyc_id)

    # H1: the only approved KYC
    order.investor_kyc_id ||= approved.first if approved.one?
    # X2: several and none picked
    return "Choose the investing entity for this subscription." if order.investor_kyc_id.nil?

    nil
  end

  # 3. Worked examples X10, E13
  def check_subscription
    return nil unless order.subscription?
    return "Enter an amount greater than zero" unless order.amount_cents.to_d.positive?

    existing = order.capital_commitment.present? && order.units_held.positive?
    min = existing ? term.min_additional_subscription_cents : term.min_initial_subscription_cents
    "Minimum subscription is #{money(min)}" if order.amount_cents.to_d < min.to_d
  end

  # 4. Worked example X13
  def check_form
    return nil unless order.redemption?

    # X126: exactly one form — units together with "all units" is refused, not silently treated as all units
    given = [order.units.present?, order.amount_cents.present?, order.all_units].count(true)
    return "Enter #{label(:units)}, amount or all #{label(:units)} — only one" unless given == 1

    # X49: units or an amount must be positive (−100 would otherwise pass the free-units check)
    bad_value = (order.units.present? && !order.units.to_d.positive?) || (order.amount_cents.present? && !order.amount_cents.to_d.positive?)
    return "Enter #{label(:units)} or an amount greater than zero" if bad_value
    return nil if setting.redemption_form_allowed?(order.form)

    # The forms in the fund's wording: "units" / "shares", "all units" / "all shares"
    words = { "all" => "all #{label(:units)}", "units" => label(:units) }
    allowed = setting.redemption_forms.map { |f| words.fetch(f, f) }
    "This fund accepts redemptions in #{allowed.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')} only"
  end

  def requested_units
    @requested_units ||= order.resolved_units
  end

  def queued_units
    @queued_units ||= DealingOrder.where(capital_commitment_id: order.capital_commitment_id, unit_type: order.unit_type, kind: "redemption",
                                         status: DealingOrder::OPEN_STATUSES).where.not(id: order.id)
                                  .sum { |o| o.all_units ? o.free_units : o.resolved_units }
  end

  # 5. Worked example X12
  def check_free_units
    return nil unless order.redemption?
    return "This #{EvergreenLabels.lower(label(:capital_commitment))} has no #{label(:units)} to redeem" if order.capital_commitment.nil?

    # Free = held − redeemed-but-unpaid; queued orders take the rest
    held = order.free_units
    return nil if requested_units <= held - queued_units

    "You hold #{number(held)} #{label(:units)}; #{number(queued_units)} are already queued for redemption."
  end

  # 6./7. Units still inside the lock-up at the dealing date: hard refuses, soft records the fee.
  # Lots are consumed oldest first. Worked examples X14, E16, E5
  def check_lock_up
    return nil unless order.redemption? && term.lock_up?

    # Judged per lot at the dealing date (EvergreenLockUp): E80–E86, X40–X44
    lock = EvergreenLockUp.call(order, on: order.dealing_date&.date || Time.zone.today, requested: requested_units, queued: queued_units)
    return nil unless lock.locked_units.positive?

    # X14 / X40: hard lock-up refuses, naming when the last locked unit used unlocks
    return "#{number(lock.locked_units)} of these #{label(:units)} are locked until #{I18n.l(lock.locked_until, format: :day_month_year)}." if term.hard_lock_up?

    # E16 / E86: soft lock-up records the units-weighted fee; pricing charges each lot at its own rate
    order.early_fee_pct = lock.blended_pct
    order.locked_units = lock.locked_units
    order.fee_breakdown = lock.breakdown
    nil
  end

  # 8. Worked example X15
  def check_min_holding
    return nil unless order.redemption? && !order.all_units && term.min_holding_cents.to_d.positive?

    nav = FundNav.latest_approved(fund, order.unit_type, Time.zone.today)
    return nil unless nav

    left = (order.units_held - queued_units - requested_units) * nav.nav_per_unit_cents.to_d
    return nil if left >= term.min_holding_cents.to_d || left <= 0

    "This would leave #{money(left)}, below the #{money(term.min_holding_cents)} minimum holding. Redeem all #{label(:units)} instead."
  end

  def number(value)
    ActionController::Base.helpers.number_with_precision(value, precision: 2, delimiter: ",", strip_insignificant_zeros: true)
  end
end
