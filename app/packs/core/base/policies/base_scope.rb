class BaseScope
  def initialize(user, scope)
    @user = user
    @scope = scope
  end

  def resolve
    if user.entity_type == "Group Company"
      scope.where(entity_id: user.entity.child_ids)
    else
      scope.where(entity_id: user.entity_id)
    end
  end

  def resolve_admin
    if user.has_cached_role?(:super) || instance_of?(::Audited::AuditPolicy::Scope) || instance_of?(ReportPolicy::Scope) || instance_of?(QuickLinkPolicy::Scope) || instance_of?(QuickLinkStepPolicy::Scope)
      scope
    elsif user.has_cached_role?(:support)
      scope.joins(entity: :support_client_mappings).where(support_client_mappings: { user_id: user.id, enabled: true }).merge(Entity.where_permissions(:enable_support))
    else
      scope.none
    end
  end

  private

  attr_reader :user, :scope
end
