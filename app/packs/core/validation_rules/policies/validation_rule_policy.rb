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
  def company_admin_for_record?
    if record.entity_id.nil?
      user.has_role?(:company_admin, :any)
    else
      user.has_role?(:company_admin, record.entity)
    end
  end
end
