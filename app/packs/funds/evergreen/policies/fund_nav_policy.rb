# NAVs: GP users of the fund draft, override and upload; approvers approve and reopen. Approval needs
# only the approver role — who drafted or overrode the NAV doesn't matter (review fix 1, 10 Oct 2026:
# the role is the control; the audit trail records who drafted, overrode and approved). A stale draft
# can't be approved (review fix 2, FundNavApprove). Investors see approved NAVs only.
# Worked examples H6, E12, X8 — openspec/changes/open-ended-funds/design.md#worked-examples
class FundNavPolicy < EvergreenBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      user.curr_role == "investor" ? super.where(status: "approved") : super
    end
  end

  def show?
    entity_enabled? && (fund_employee?(:read) || (fund_investor? && record.approved?))
  end

  def update?
    super && record.draft?
  end

  def destroy?
    update?
  end

  def import?
    create?
  end

  def approve?
    # The approver role is mandatory; an approver may approve a NAV they prepared (small funds), audited
    entity_enabled? && record.draft? && approver? && fund_employee?(:update)
  end

  # Deciding a late management fee is part of approving the draft (R9.13): same people, same rights (X205)
  def decide_late_fee?
    approve?
  end

  def reopen?
    entity_enabled? && record.approved? && approver? && fund_employee?(:update)
  end
end
