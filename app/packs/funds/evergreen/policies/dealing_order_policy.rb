# Orders: GP users of the fund see and enter any order; approvers accept / reject; investors place,
# see and cancel only their own (an investor of another fund, or another entity, sees nothing).
# Worked examples H7, H11, E20, X19 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingOrderPolicy < EvergreenBasePolicy
  def show?
    entity_enabled? && (fund_employee?(:read) || own_order?)
  end

  def create?
    return false unless entity_enabled?

    fund_employee?(:update) || (fund_investor? && (record.investor_id.blank? || own_investor_ids.include?(record.investor_id)))
  end

  def preview?
    create?
  end

  # The investor's signed subscription form: a pending subscription, by the investor or a GP editor
  def upload_form?
    entity_enabled? && record.subscription? && record.pending? && (own_order? || fund_employee?(:update))
  end

  def cancel?
    entity_enabled? && record.cancellable? && (fund_employee?(:update) || own_order?)
  end

  def accept?
    entity_enabled? && record.pending? && record.accepted_at.nil? && approver? && fund_employee?(:update)
  end

  def reject?
    accept?
  end

  def verify_signatory?
    entity_enabled? && record.pending? && fund_employee?(:update)
  end

  # Recording pre-funded money on the order: GP editors, pending subscriptions with a payment row
  # Accept a part payment as the whole subscription: fund editors, part-paid, units not yet allotted
  def accept_received?
    entity_enabled? && fund_employee?(:update) && record.part_paid? &&
      !record.dealing_fills.where(kind: "subscription").where.not(fund_unit_id: nil).exists?
  end

  def record_payment?
    entity_enabled? && record.subscription? && record.pending? && record.capital_remittance.present? && fund_employee?(:update)
  end

  def import?
    entity_enabled? && fund_employee?(:update)
  end

  private

  def own_order?
    fund_investor? && own_investor_ids.include?(record.investor_id)
  end

  # Investors of this fund's entity that the user has approved access to
  def own_investor_ids
    @own_investor_ids ||= InvestorAccess.approved_for_user(user).where(entity_id: fund.entity_id).pluck(:investor_id)
  end
end
