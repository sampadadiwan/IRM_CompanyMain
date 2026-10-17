class ValidationRuleOverridePolicy < ApplicationPolicy
  def index?   = admin_user? || company_admin_for_entity?
  def show?    = admin_user? || company_admin_for_entity?
  def create?  = admin_user? || company_admin_for_entity?
  def update?  = admin_user? || company_admin_for_entity?
  def destroy? = admin_user? || company_admin_for_entity?

  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super) || user.has_cached_role?(:support)
        scope.all
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  private

  def admin_user?
    user.has_cached_role?(:super) || user.has_cached_role?(:support)
  end

  def company_admin_for_entity?
    # When authorizing the class (index action), any company_admin may proceed —
    # the controller scopes the data to their own entity anyway
    return user.has_cached_role?(:company_admin) if record.is_a?(Class)

    entity = record.is_a?(ValidationRuleOverride) ? record.entity : nil
    entity ||= Entity.find_by(id: record.entity_id)
    # Never fall through to :any — an override with no resolvable entity cannot be authorized
    return false unless entity

    # B4-6: the cached role plus membership of that entity (has_role? with a resource also matched
    # a company admin of any entity).
    user.has_cached_role?(:company_admin) &&
      (user.entity_id == entity.id || (user.entity_type == "Group Company" && user.entity.child_ids.include?(entity.id)))
  end
end
