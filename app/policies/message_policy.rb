class MessagePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where('deal_investors.entity_id': user.entity_id).joins(:deal_investor)
      end
    end
  end

  def index?
    true
  end

  def show?
    if user.entity_id == record.entity_id
      true
    else
      record.owner && record.owner.entity_id == user.entity_id
    end
  end

  def mark_as_task?
    create?
  end

  def task_done?
    create?
  end

  def create?
    if user.entity_id == record.owner.entity_id
      true
    else
      record.investor && record.investor.investor_entity_id == user.entity_id
    end
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
