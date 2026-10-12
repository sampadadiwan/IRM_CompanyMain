# Accepts a subscription or redemption order from the portal wizard, an admin or an upload:
# validate (OrderEligibility) → dealing date from cut-off / notice → save → for a pre-funded
# subscription open / top up the folio and create its subscription payment → acknowledgement email.
# Order journeys launch through the existing auto-assignment rule (DealingOrder#skip_journey?).
# Worked examples H7, H8, H9, E13–E18, X10–X16 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingOrderCreate < Trailblazer::Operation
  step :build
  step :check_ownership
  step :assign_dealing_date
  step :check_eligibility
  step :persist
  step :acknowledge

  def build(ctx, fund:, params:, current_user:, source: "portal", **)
    attrs = params.to_h.symbolize_keys
    order = DealingOrder.new(
      entity_id: fund.entity_id, fund:, kind: attrs[:kind], unit_type: attrs[:unit_type], source:,
      investor_id: attrs[:investor_id], capital_commitment_id: attrs[:capital_commitment_id].presence,
      # The investing entity picked on the form / import; OrderEligibility#check_kyc validates or fills it (evergreen-folio-soa ①)
      investor_kyc_id: attrs[:investor_kyc_id].presence,
      amount_cents: cents(attrs[:amount]), units: attrs[:units].presence&.to_s&.delete(",")&.to_d,
      all_units: ActiveModel::Type::Boolean.new.cast(attrs[:all_units]) || false, note: attrs[:note],
      received_at: attrs[:received_at].presence ? Time.zone.parse(attrs[:received_at].to_s) : Time.current,
      entered_by: source == "portal" ? nil : current_user, import_upload_id: ctx[:import_upload]&.id
    )
    # Admin entry by folio number
    order.capital_commitment ||= fund.capital_commitments.find_by(folio_id: attrs[:folio_id]) if attrs[:folio_id].present?
    order.investor_id ||= order.capital_commitment&.investor_id
    ctx[:order] = order
  end

  # The folio must be this fund's and the investor's; the investor must belong to the fund's entity
  def check_ownership(ctx, fund:, order:, **)
    folio = order.capital_commitment
    # "a folio" / "an account": the fund's word for a folio, with its article
    a_folio = EvergreenLabels.t(:capital_commitment, fund:, lower: true, article: true)
    ctx[:errors] = if order.investor_id.present? && !Investor.exists?(id: order.investor_id, entity_id: fund.entity_id)
                     "Choose an investor of this fund"
                   elsif folio && (folio.fund_id != fund.id || (order.investor_id.present? && folio.investor_id != order.investor_id))
                     "Choose #{a_folio} of this investor in this fund"
                   end
    ctx[:errors].nil?
  end

  # Worked examples E14, E15
  def assign_dealing_date(ctx, fund:, order:, **)
    if order.investor_id.blank? || DealingOrder::KINDS.exclude?(order.kind) || fund.unit_types_list.exclude?(order.unit_type.to_s)
      ctx[:errors] = "Choose an investor, a class and subscription or redemption"
      return false
    end
    setting = fund.evergreen_fund_setting
    date = DealingCalendar.next_dealing_date(setting, order.kind, order.unit_type, order.received_at)
    order.dealing_date = DealingDate.for(fund, date)
    # A date already confirmed (early, or before a back-dated entry) takes no more orders: move to the
    # next open dealing date of this kind (review finding: orders stranded on confirmed dates)
    until order.dealing_date.open?
      date = DealingCalendar.dates(setting, order.kind, from: date + 1.day, to: date + DealingCalendar::HORIZON_YEARS.years).first
      raise DealingCalendar::NoDate, "No open #{EvergreenLabels.lower(EvergreenLabels.t(order.subscription? ? :subscription_date : :redemption_date, fund:))} is available — check the fund's dealing calendar" unless date

      order.dealing_date = DealingDate.for(fund, date)
    end
    true
  rescue DealingCalendar::NoDate => e
    ctx[:errors] = e.message
    false
  end

  def check_eligibility(ctx, order:, **)
    errors = OrderEligibility.errors_for(order)
    ctx[:errors] = errors.first
    errors.empty?
  end

  # Pre-funded subscriptions need their folio and payment row now, so money can arrive before dealing.
  # One transaction: a failure leaves no half-made order.
  def persist(ctx, fund:, order:, current_user:, **)
    ActiveRecord::Base.transaction do
      # Lock the dealing date so a confirm running right now can't price without this order
      order.dealing_date.lock!
      raise(ActiveRecord::RecordInvalid, order.tap { |o| o.errors.add(:base, "The #{EvergreenLabels.lower(EvergreenLabels.t(o.subscription? ? :subscription_date : :redemption_date, fund:))} was just confirmed — please submit again") }) unless order.dealing_date.open?

      order.save!
      if order.subscription? && fund.evergreen_fund_setting.pre_funded?
        FolioOpener.call(order, current_user)
        DealingSettlement.ensure_subscription_payment(order, current_user)
      end
    end
    true
  rescue ActiveRecord::RecordInvalid, FolioOpener::Error, DealingSettlement::Error => e
    ctx[:errors] = e.message
    false
  end

  def acknowledge(_ctx, order:, **)
    EvergreenNotifier.order_received(order)
    # Internal alerts: new portal order → relationship manager; large redemption → Compliance (§ Notifications)
    EvergreenAlerts.order_placed(order)
    true
  end

  private

  def cents(amount)
    return nil if amount.blank?

    amount.to_s.delete(",").to_d * 100
  end
end
