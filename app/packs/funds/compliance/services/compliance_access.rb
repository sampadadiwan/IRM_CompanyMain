# ⑦ Who may do what in Compliance (Roles and access, R6, R11, E15):
#   viewer   — the existing enable_compliance flag (user + entity), employees of the fund's firm only
#   editor   — viewer + (company admin or the compliance_edit flag)
#   approver — viewer + (company admin or the compliance_approve flag)
# Investors and investor advisors are never viewers (X22). Fund access still applies (X20).
module ComplianceAccess
  module_function

  def employee?(user)
    user.present? && !user.investor_advisor? &&
      (user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee)) &&
      !user.has_cached_role?(:investor)
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
    User.where(entity_id: entity.id, active: true).select { |u| approver?(u) }
  end

  # Fund ids the user may see (fund access rights for non-admin employees — X20, E47)
  def fund_ids(user)
    Pundit.policy_scope(user, Fund).where(entity_id: user.entity_id).pluck(:id)
  end

  def fund_visible?(user, fund)
    fund.present? && fund.entity_id == user.entity_id && Pundit.policy(user, fund).show?
  end
end
