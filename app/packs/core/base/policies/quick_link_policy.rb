class QuickLinkPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        scope.where(entity_id: [user.entity_id, nil])
      elsif user.entity.is_fund? || user.entity.is_group_company?
        scope.where(entity_id: [user.entity_id, nil])
      elsif user.has_cached_role?(:super)
        scope.all
      else
        scope.none
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || record.entity.nil?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
