class CapitalCallPolicy < FundBasePolicy
  include WorkflowablePolicyMethods # journey?, assign_workflow?

  def index?
    user.enable_funds
  end

  def create?
    permissioned_employee?(:create)
  end

  def show?
    permissioned_employee?
  end

  # The stats cards frame is part of the show page, so the same people can load it
  def stats?
    show?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def approve?
    !record.approved && update? && user.has_cached_role?(:approver)
  end

  def unapprove?
    record.approved && update? && user.has_cached_role?(:approver)
  end

  def edit?
    update?
  end

  def recompute_fees?
    update?
  end

  def generate_docs?
    !record.approved && update?
  end

  def allocate_units?
    record.approved && record.unit_prices.present? && update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update? && record.approved
  end

  def notify?
    update? && record.approved
  end

  def run_agent?
    permissioned_employee?(:update)
  end

  # Confirming/reassigning a reconciliation deposit is the same permission as running the
  # agent itself — both create a CapitalRemittancePayment on this call's behalf.
  def confirm_reconciliation_deposit?
    run_agent?
  end

  def reassign_reconciliation_deposit?
    run_agent?
  end

  def confirm_all_exact_reconciliation_deposits?
    run_agent?
  end

  # Undoing a reconciliation payment deletes a CapitalRemittancePayment, so it needs the same
  # destroy permission the payment's own controller checks, not just run/update.
  def undo_reconciliation_deposit?
    run_agent? && permissioned_employee?(:destroy)
  end
end
