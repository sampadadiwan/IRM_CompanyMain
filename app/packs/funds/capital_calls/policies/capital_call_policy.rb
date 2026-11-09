class CapitalCallPolicy < FundBasePolicy
  include WorkflowablePolicyMethods # journey?, assign_workflow?
  # M13 (OWASP 2026-11) K9 / K11 — maker–checker: maker_checker_allows?, awaiting_second_approver?, request_approval?
  include MakerCheckerPolicyMethods

  # H18 — capital calls are staff-only records: no LP screen, mobile endpoint or MCP answer is meant to list
  # them. FundBasePolicy's investor branch would list every one in a fund the LP can see, so an investor
  # persona (an LP, an advisor switched to investor) gets none. The RM branch is FundBasePolicy's, unchanged.
  # Tests H18-3, H18-X1 — features/security/lp_staff_only_fund_lists.feature
  class Scope < FundBasePolicy::Scope
    def resolve
      # Investor persona (but not an RM, who keeps FundBasePolicy's RM branch): nothing
      return scope.none if user.curr_role_investor? && !user.has_cached_role?(:rm)

      # Staff, RMs and support: FundBasePolicy's scope, as before
      super
    end
  end

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

  # H12 / X3 / X10 (M13) — with the firm's maker–checker setting on, a preparer of the call can't approve it; every
  # path (button, URL, JSON API, bulk) asks this one method. Setting off (the default): exactly as before.
  def approve?
    !record.approved && update? && user.has_cached_role?(:approver) && maker_checker_allows?
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
