class EventPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %w[employee].include?(user.curr_role)
        scope.where(entity_id: user.entity_id)
      elsif user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.none
      end
    end
  end

  def index?
    belongs_to_entity?(user, record)
  end

  def new?
    index?
  end

  def create?
    index?
  end

  def show?
    create?
  end

  def edit?
    create?
  end

  def update?
    edit?
  end
end
