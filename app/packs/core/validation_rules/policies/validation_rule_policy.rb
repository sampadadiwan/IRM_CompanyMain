class ValidationRulePolicy < ApplicationPolicy
  # Super/support users access via the admin panel; company_admins via the tenant UI
  def index?   = admin_user? || company_admin_for_record?
  def show?    = admin_user? || company_admin_for_record?
  def create?  = admin_user? || company_admin_for_record?
  def update?  = admin_user? || company_admin_for_record?
  def destroy? = admin_user? || company_admin_for_record?

  # All authenticated users can hit the evaluate endpoint (it reads, never writes)
  def evaluate? = true

  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super) || user.has_cached_role?(:support)
        scope.all
      else
        # Company admins see global defaults + their own entity's custom rules
        scope.where(entity_id: [nil, user.entity_id])
      end
    end
  end

  private

  def admin_user?
    user.has_cached_role?(:super) || user.has_cached_role?(:support)
  end

  # Global default rules (entity_id nil) are visible to any company_admin;
  # entity-specific rules are visible only to that entity's company_admin.
  # B4-6: has_role?(:company_admin, entity) also matched the global role, i.e. an admin of any
  # entity. A company admin manages their own entity's rules (and a group's children's); global
  # rules (entity nil) stay visible to any company admin, as before.
  # Worked example B4-6 — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
  def company_admin_for_record?
    return false unless user.has_cached_role?(:company_admin)
    return true if record.entity_id.nil?

    belongs_to_entity?(user, record)
  end
end
