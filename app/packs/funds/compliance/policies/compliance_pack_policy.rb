# ① Rule Library. CapHive packs: super admins author; customers see published ones only (H1).
# Entity packs: visible and editable only inside their own firm (X12). Locked packs are never
# customer-editable (X13, X55, E102).
class CompliancePackPolicy < ComplianceBasePolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.has_cached_role?(:super)
      return scope.none unless ComplianceAccess.viewer?(user)

      published = CompliancePackVersion.where(status: "published").select(:compliance_pack_id)
      scope.where(entity_id: user.entity_id).or(scope.where(entity_id: nil, id: published))
    end
  end

  def index?
    super_admin? || viewer?
  end

  def show?
    return true if super_admin?
    return false unless viewer?

    record.entity_id == user.entity_id || (record.entity_id.nil? && record.latest_published_version.present?)
  end

  def create?
    super_admin? || editor?
  end

  # Editing a pack's rules: CapHive packs by super admins only; entity packs by the firm's editors
  def update?
    return super_admin? if record.caphive?

    editor? && same_firm?
  end

  def retire?
    super_admin? && record.caphive?
  end
end
