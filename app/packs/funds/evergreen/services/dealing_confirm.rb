# Confirms a dealing date (design card ⑤): re-prices under a lock, refuses if the price changed since
# the user's preview, stores one fill per priced order, rolls or cancels orders not ready, carries
# gated redemptions forward, settles through the existing records — all in one transaction — then
# (after commit) allots units for paid pre-funded subscriptions and sends notices.
# Worked examples H21, H25, E6, E23–E25, E34, X17, X20 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingConfirm < Trailblazer::Operation
  class PricingChanged < StandardError; end

  step :confirm
  step :after_commit_work

  # X17: shown on the workspace and when a confirm is refused
  def self.missing_nav_message(unit_type, nav, dealing_date)
    # Decision 4: an approved NAV the previous dealing date already priced at — ask for a newer one
    if nav&.approved? && (previous = DealingPricer.reused_on(nav, dealing_date))
      return "Class #{unit_type}'s #{I18n.l(nav.nav_date, format: :day_month_year)} NAV already priced " \
             "#{I18n.l(previous.date, format: :day_month_year)} — draft and approve a newer NAV first"
    end

    dated = nav ? nav.nav_date : dealing_date.date
    "Approve the NAV for Class #{unit_type} dated #{I18n.l(dated, format: :day_month_year)} first"
  end

  def confirm(ctx, dealing_date:, current_user:, preview_hash: nil, **)
    ActiveRecord::Base.transaction do
      dealing_date.lock!
      raise ArgumentError, "This #{EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: dealing_date.fund))} is already confirmed" unless dealing_date.open?

      pricing = DealingPricer.preview(dealing_date)
      # Lock the NAVs being priced at, so a reopen can't slip in between pricing and the fills
      FundNav.where(id: pricing.navs.values.compact.map(&:id)).lock.load
      check!(pricing, dealing_date, preview_hash)
      store_fills(dealing_date, pricing)
      rolled = DealingRoll.call(dealing_date, pricing.unready, current_user)
      carried = carry_forward(dealing_date, pricing, current_user)
      DealingSettlement.settle(dealing_date.reload, current_user)
      dealing_date.update!(status: "confirmed", confirmed_by: current_user, confirmed_at: Time.current,
                           settings_snapshot: dealing_date.fund.evergreen_fund_setting.attributes.except("id", "created_at", "updated_at"),
                           gate_snapshot: pricing.gate.merge(rolled:, carried:).as_json)
      ctx[:pricing] = pricing
      ctx[:rolled] = rolled
    end
    true
  rescue PricingChanged, ArgumentError, DealingSettlement::Error, FolioOpener::Error => e
    ctx[:errors] = e.message
    false
  end

  # After commit: allot units for subscriptions already paid (pre-funded), and send gate notices,
  # roll / cancel emails and pay-after payment instructions
  def after_commit_work(ctx, dealing_date:, current_user:, **)
    dealing_date.subscription_fills.includes(:capital_remittance).find_each do |fill|
      if dealing_date.pre_funded?
        DealingSettlementSyncJob.perform_later("CapitalRemittance", fill.capital_remittance_id, current_user&.id) if fill.capital_remittance&.verified
      else
        EvergreenNotifier.payment_instructions(fill)
        fill.update!(instructions_sent_at: Time.current)
      end
    end
    dealing_date.redemption_fills.where("carried_units > 0").find_each { |fill| EvergreenNotifier.gate_notice(fill) }
    DealingOrder.where(id: ctx[:rolled]["rolled"]).find_each { |o| EvergreenNotifier.order_rolled(o) }
    DealingOrder.where(id: ctx[:rolled]["cancelled"]).find_each { |o| EvergreenNotifier.order_cancelled(o) }
    dealing_date.journey_progress!(actor: current_user)
    # Gate applied → Compliance and Fund ops (§ Notifications)
    EvergreenAlerts.dealing_confirmed(dealing_date)
    true
  end

  private

  def check!(pricing, dealing_date, preview_hash)
    # Decision 3: never before the last deadline (subscription cut-off / every class's notice) has
    # passed — orders placed on time could still arrive or be paid. The screen shows the same message.
    if (blocked = dealing_date.deadline_block_message)
      raise ArgumentError, blocked
    end

    if pricing.missing_navs.any?
      ut, nav = pricing.missing_navs.first
      raise ArgumentError, missing_nav_message(ut, nav, dealing_date)
    end
    # X57 / E181: refused only when there is nothing at all; not-ready orders alone are rolled / cancelled
    raise ArgumentError, "Nothing to deal on #{I18n.l(dealing_date.date, format: :day_month_year)}" if pricing.empty? && pricing.unready.empty?
    raise PricingChanged, "Pricing changed — review again" if preview_hash.present? && preview_hash != pricing.hash_key
  end

  def missing_nav_message(...)
    self.class.missing_nav_message(...)
  end

  def store_fills(dealing_date, pricing)
    pricing.subscriptions.each do |row|
      create_fill(dealing_date, row.order, row.nav, kind: "subscription", requested_units: row.units, units: row.units,
                                                    amount_cents: row.amount_cents)
      row.order.update!(status: "dealt")
    end
    pricing.redemptions.each do |row|
      create_fill(dealing_date, row.order, row.nav, kind: "redemption", requested_units: row.requested_units, units: row.filled_units,
                                                    amount_cents: row.value_cents, carried_units: row.carried_units, early_fee_cents: row.early_fee_cents)
      # Nothing filled: still pending, moved to the next date with its queue place (E3 C HUF)
      status = if row.filled_units.zero? then "pending"
               elsif row.carried_units.positive? then "partially_filled"
               else "dealt"
               end
      row.order.update!(status:)
    end
  end

  def create_fill(dealing_date, order, nav, **attrs)
    DealingFill.create!(entity_id: dealing_date.entity_id, fund_id: dealing_date.fund_id, dealing_date:, dealing_order: order,
                        fund_nav: nav, unit_type: order.unit_type, nav_per_unit_cents: nav.nav_per_unit_cents, **attrs)
  end

  # Gated redemptions keep their received time and move to the next redemption date (H26)
  def carry_forward(dealing_date, pricing, user)
    pricing.redemptions.select { |r| r.carried_units.positive? }.filter_map do |row|
      # Nowhere to carry to (calendar ran out): close the order on what was filled, saying so
      if DealingRoll.next_date(row.order, dealing_date).nil?
        row.order.update!(status: "dealt", rejected_reason: "No later redemption date in the calendar — the rest was not carried")
        next
      end
      DealingRoll.move(row.order, dealing_date, user, count_roll: false)
      row.order.id
    end
  end
end
