# Opens or tops up an evergreen investor's folio (an existing CapitalCommitment under the hood):
# a new folio gets the subscription as its committed ("subscribed") amount and the order's KYC; an existing one gets a
# "Top Up" CommitmentAdjustment owned by the order, so cancel / undo can reverse it.
# Worked examples H7, H22, E31 — openspec/changes/open-ended-funds/design.md#worked-examples
class FolioOpener
  class Error < StandardError; end

  # Returns the folio for the order (opening one if needed) and records the top-up.
  def self.call(order, user)
    order.capital_commitment ? top_up(order, user) : open_folio(order, user)
  end

  def self.open_folio(order, user)
    fund = order.fund
    # Serialise folio numbering per fund (callers are inside a transaction), so two orders opening
    # folios at once can't both take the same F-number (review finding)
    Fund.where(id: fund.id).lock.pick(:id)
    folio = CapitalCommitment.new(
      entity_id: fund.entity_id, fund:, investor: order.investor, unit_type: order.unit_type, investor_kyc_id: folio_kyc_id(order),
      folio_id: next_folio_id(fund), folio_currency: fund.currency, fund_close: fund.evergreen_fund_setting.fund_close_name,
      commitment_date: order.received_at.to_date, folio_committed_amount_cents: order.amount_cents,
      orig_folio_committed_amount_cents: order.amount_cents, notes: "Opened by evergreen subscription"
    )
    result = CapitalCommitmentCreate.call(capital_commitment: folio, current_user: user)
    raise Error, result[:errors].presence || folio.errors.full_messages.to_sentence unless result.success?

    order.update!(capital_commitment: folio)
    folio
  end

  # Every evergreen folio carries the KYC its order recorded (OrderEligibility#check_kyc). An order
  # placed before orders recorded one falls back to the investor's only approved KYC.
  # evergreen-folio-soa: H1 / H2 / E1 the order's KYC; X5 none → the folio isn't opened
  def self.folio_kyc_id(order)
    return order.investor_kyc_id if order.investor_kyc_id

    approved = InvestorKyc.where(entity_id: order.entity_id, investor_id: order.investor_id, verified: true).limit(2).pluck(:id)
    raise Error, "#{order.investor.investor_name} has no single approved KYC for this order — choose the investing entity on the order" unless approved.one?

    order.update_column(:investor_kyc_id, approved.first)
    approved.first
  end

  def self.top_up(order, user)
    folio = order.capital_commitment
    adjustment = CommitmentAdjustment.new(
      entity_id: folio.entity_id, fund_id: folio.fund_id, capital_commitment: folio, owner: order,
      adjustment_type: "Top Up", as_of: [order.received_at.to_date, folio.commitment_date].compact.max,
      folio_amount_cents: order.amount_cents, amount_cents: order.amount_cents,
      reason: "Evergreen subscription #{order.id}"
    )
    result = AdjustmentCreate.call(commitment_adjustment: adjustment, current_user: user)
    raise Error, result[:errors].presence || adjustment.errors.full_messages.to_sentence unless result.success?

    folio
  end

  # Reverse a top-up made for an order (cancel / undo). A folio opened for this order alone, with
  # nothing else in it, is removed.
  def self.reverse(order, user)
    CommitmentAdjustment.where(owner: order).find_each do |adj|
      AdjustmentDestroy.call(commitment_adjustment: adj, current_user: user)
    end
    folio = order.capital_commitment
    return unless folio && folio.notes == "Opened by evergreen subscription"
    return if FundUnit.exists?(capital_commitment_id: folio.id)
    return if DealingOrder.where(capital_commitment_id: folio.id).where.not(id: order.id).exists?

    order.update!(capital_commitment: nil)
    folio.capital_remittances.each(&:destroy)
    folio.destroy
  end

  # F-<n>: one past the fund's highest numeric F- folio number, never below F-101 (so migrated
  # folios F-001..F-099 and new evergreen folios stay apart)
  def self.next_folio_id(fund)
    last = fund.capital_commitments.where("folio_id LIKE 'F-%'").pluck(:folio_id).filter_map { |f| f[2..].to_i if /\A\d+\z/.match?(f[2..]) }.max
    "F-#{[last.to_i, 100].max + 1}"
  end
end
