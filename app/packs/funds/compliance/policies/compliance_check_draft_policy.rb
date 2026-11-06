# ⑧ "Describe in words" drafts. Drafting writes into a pack version, so it needs the same right as editing
# that version (editors of the firm for entity packs, super admins for CapHive packs); viewers are refused
# (X43). A draft is only ever seen by the person who made it.
# Worked examples X43, E64 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckDraftPolicy < ComplianceBasePolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.has_cached_role?(:super) || ComplianceAccess.editor?(user)

      scope.where(user_id: user.id)
    end
  end

  def create?
    Pundit.policy(user, record.compliance_pack_version).update?
  end

  def show?
    record.user_id == user.id && create?
  end

  def update?
    show? && !record.saved?
  end

  def test_run?
    update?
  end

  def save_check?
    update?
  end
end
