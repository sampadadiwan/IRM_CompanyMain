# ⑦ Who may do what in Compliance (Roles and access, R6, R11, E15):
#   viewer   — the existing enable_compliance flag (user + entity), employees of the fund's firm only
#   editor   — viewer + (company admin or the compliance_edit flag)
#   approver — viewer + (company admin or the compliance_approve flag)
# Investors (users acting as an investor) and investor advisors are never viewers (X22, E138).
# Fund access still applies (X20).
module ComplianceAccess
  module_function

  # Fund-side staff acting as staff. Like ApplicationPolicy#permissioned_investor_non_advisor?, a user
  # counts as an investor by the role they are acting in (curr_role), not by holding the role at all:
  # many GP employees also hold an investor role (e.g. they invest in their own fund) and must still
  # see Compliance; the same user switched to their investor role is refused (X22, E138, R109).
  def employee?(user)
    user.present? && !user.investor_advisor? && !user.curr_role_investor? &&
      (user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee))
  end

  # The firm has bought Compliance: the existing enable_compliance entity flag (shared with AI Rules, R114).
  # Background work (runs, digests, reading, drafting) and Run now stop when it is off (X69).
  def entity_enabled?(entity)
    entity.present? && entity.permissions.enable_compliance?
  end

  def viewer?(user)
    employee?(user) && user.enable_compliance
  end

  def editor?(user)
    viewer?(user) && (user.has_cached_role?(:company_admin) || user.get_extended_permissions.set?(:compliance_edit))
  end

  def approver?(user)
    viewer?(user) && (user.has_cached_role?(:company_admin) || user.get_extended_permissions.set?(:compliance_approve))
  end

  # Active users of the entity who can approve (company admins included — H59)
  def eligible_approvers(entity)
    # roles/entity preloaded: approver? checks roles and the entity flag per user (Prosopite, R176)
    User.where(entity_id: entity.id, active: true).includes(:roles, :entity).select { |u| approver?(u) }
  end

  # Fund ids the user may see (fund access rights for non-admin employees — X20, E47)
  def fund_ids(user)
    Pundit.policy_scope(user, Fund).where(entity_id: user.entity_id).pluck(:id)
  end

  def fund_visible?(user, fund)
    fund.present? && fund.entity_id == user.entity_id && Pundit.policy(user, fund).show?
  end
end
