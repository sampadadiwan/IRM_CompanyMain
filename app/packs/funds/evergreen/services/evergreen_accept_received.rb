# "Accept received amount": a part-paid subscription becomes the amount actually received
# (open-ended-funds § Accept received amount). Example: ₹1 Cr ordered, ₹50 L received →
#  - before dealing (pending, pre-funded): the order is for ₹50 L and is dealt as fully paid;
#  - after dealing (pay-after fill priced at the dealing NAV): the fill is re-sized to ₹50 L at the
#    same NAV per unit, and units are allotted for ₹50 L.
# The payment row's amount and the folio's subscribed amount (a negative "Top Up" owned by the order)
# drop by the shortfall. One-way: money arriving later is an excess to refund.
class EvergreenAcceptReceived < Trailblazer::Operation
  step :check
  step :accept

  def check(ctx, order:, **)
    rem = order.capital_remittance
    received = rem&.collected_amount_cents.to_d
    ctx[:errors] = if !order.subscription? then "Only a subscription can be accepted at the amount received"
                   elsif rem.nil? || !received.positive? then "No money has been received for this subscription — cancel it instead"
                   elsif received >= rem.call_amount_cents.to_d then "This subscription is already fully paid"
                   elsif fill(order)&.fund_unit_id then "#{EvergreenLabels.t(:Units, fund: order.fund)} are already allotted for this subscription"
                   elsif !order.pending? && fill(order).nil? then "This order is no longer pending"
                   end
    ctx[:received] = received
    ctx[:errors].nil?
  end

  def accept(_ctx, order:, received:, current_user:, **)
    rem = order.capital_remittance
    shortfall = rem.call_amount_cents.to_d - received
    ActiveRecord::Base.transaction do
      order.lock!
      order.update!(original_amount_cents: order.original_amount_cents || order.amount_cents, amount_cents: received,
                    amount_reduced_by: current_user, amount_reduced_at: Time.current,
                    audit_comment: "Subscription reduced to the amount received (#{shortfall / 100} short)")
      # After dealing: re-size the fill at the same dealing NAV per unit
      if (f = fill(order))
        f.update!(amount_cents: received, units: (received / f.nav_per_unit_cents.to_d).round(8))
      end
      # The payment row asks only for what was received …
      rem.update!(call_amount_cents: received, folio_call_amount_cents: received)
      # … and the folio's subscribed amount drops by the shortfall
      reduce_folio(order, shortfall, current_user)
    end
    # Fully paid now: verify (the remittance hook then allots units when the date is settled)
    EvergreenPayments.verify(rem.reload, current_user)
    CapitalRemittancesCountersJob.perform_later([order.fund_id], current_user&.id, rem.capital_call_id)
    order.journey_progress!
    true
  end

  private

  def fill(order)
    order.dealing_fills.where(kind: "subscription").order(:id).last
  end

  def reduce_folio(order, shortfall, user)
    folio = order.capital_commitment
    return unless folio && shortfall.positive?

    adjustment = CommitmentAdjustment.new(
      entity_id: folio.entity_id, fund_id: folio.fund_id, capital_commitment: folio, owner: order,
      adjustment_type: "Top Up", as_of: Time.zone.today, folio_amount_cents: -shortfall, amount_cents: -shortfall,
      reason: "Evergreen subscription #{order.id} reduced to the amount received"
    )
    result = AdjustmentCreate.call(commitment_adjustment: adjustment, current_user: user)
    raise ActiveRecord::RecordInvalid, adjustment unless result.success?
  end
end
