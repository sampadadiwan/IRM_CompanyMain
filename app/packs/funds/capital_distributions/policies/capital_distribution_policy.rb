class CapitalDistributionPolicy < FundBasePolicy
  include WorkflowablePolicyMethods # journey?, assign_workflow?

  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  def new?
    create?
  end

  def add_pis_to_capital_distribution?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  # Bulk "Mark Payments Completed": only once the distribution is approved. The Actions menu and the
  # request itself both ask this one method, so the server enforces what the menu shows (it used to
  # check update? only, while the menu checked a separate mark_payments_completed?).
  # Imported distributions are history: never approved in CapHive (and never emailed), so they are
  # exempt — their Light journey has no Approve step.
  # Worked examples X2, H9 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def payments_completed?
    update? && (record.approved || record.manual_generation)
  end

  def send_payment_notifications?
    update? && record.approved
  end

  def recompute_fees?
    update?
  end

  def clone?
    create?
  end

  # Approving a payout needs the Approver role, as approving a capital call does
  # Worked examples X1, H5 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def approve?
    !record.approved && update? && user.has_cached_role?(:approver)
  end

  def redeem_units?
    record.unit_prices.present? && update?
  end

  def generate_docs?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update?
  end
end
