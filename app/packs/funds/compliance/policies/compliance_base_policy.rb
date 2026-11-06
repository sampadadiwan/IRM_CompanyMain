# ⑦ Shared rules for every compliance policy (design › Security items 1–2):
#   viewer/editor/approver from ComplianceAccess; same firm; fund access for fund-scoped records (X20, X21).
# Investors and investor advisors are never viewers, so every predicate is false for them (X22).
class ComplianceBasePolicy < ApplicationPolicy
  def viewer?
    ComplianceAccess.viewer?(user)
  end

  def editor?
    ComplianceAccess.editor?(user)
  end

  def approver?
    ComplianceAccess.approver?(user)
  end

  def super_admin?
    user.has_cached_role?(:super)
  end

  def same_firm?(rec = record)
    rec.respond_to?(:entity_id) && rec.entity_id.present? && rec.entity_id == user.entity_id
  end

  def fund_visible?(fund)
    ComplianceAccess.fund_visible?(user, fund)
  end

  # Fund-scoped records: same firm and the fund is visible to the user
  def fund_scoped_visible?(rec = record)
    same_firm?(rec) && fund_visible?(rec.fund)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless ComplianceAccess.viewer?(user)

      base = scope.where(entity_id: user.entity_id)
      base.column_names.include?("fund_id") ? base.where(fund_id: ComplianceAccess.fund_ids(user)) : base
    end
  end
end
