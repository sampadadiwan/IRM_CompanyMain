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
    if instance_of?(::PaperTrail::VersionPolicy::Scope)
      scope
    else
      scope.joins(:entity).where('entities.enable_support': true)
    end
  end

  private

  attr_reader :user, :scope
end
