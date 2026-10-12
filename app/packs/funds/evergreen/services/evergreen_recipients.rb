# Named-role recipients for evergreen notifications (open-ended-funds § Notifications):
# approvers (rolify role), the investor's relationship manager (Investor#managed_by) and users tagged
# FundOps / FundAccounting / Compliance (User::NOTIFICATION_TAGS). Internal recipients must be able to
# see the fund; investor recipients come from Investor#notification_users(order or folio).
class EvergreenRecipients
  OPS = "FundOps".freeze
  ACCOUNTING = "FundAccounting".freeze
  COMPLIANCE = "Compliance".freeze

  def initialize(fund)
    @fund = fund
  end

  def approvers(except: nil)
    visible(employees.with_role(:approver)).reject { |u| except && u.id == except.id }
  end

  def tagged(tag)
    visible(employees.with_tag(tag).to_a.select { |u| u.tag_list.to_s.split(",").map(&:strip).include?(tag) })
  end

  # The investor's "Managed by" employee, else Fund ops
  def relationship_manager(investor)
    rm = investor&.managed_by
    rm&.active? && rm.entity_id == @fund.entity_id && can_see?(rm) ? [rm] : tagged(OPS)
  end

  private

  def employees
    User.where(entity_id: @fund.entity_id, active: true)
  end

  def visible(users)
    users.to_a.select { |u| can_see?(u) }.uniq
  end

  def can_see?(user)
    Pundit.policy(user, @fund).show?
  rescue StandardError
    false
  end
end
