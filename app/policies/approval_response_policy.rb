class ApprovalResponsePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif %w[startup fund_manager].index(user.curr_role)
        scope.where(entity_id: user.entity_id)
      else
        scope.where(response_entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) || (user.entity_id == record.response_entity_id)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    (user.entity_id == record.response_entity_id)
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def approve?
    (user.entity_id == record.response_entity_id)
  end
end
