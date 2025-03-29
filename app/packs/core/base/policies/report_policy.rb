class ReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: [user.entity_id, nil], curr_role: user.curr_role)
    end
  end

  def index?
    true
  end

  def prompt?
    true
  end

  def show?
    belongs_to_entity?(user, record) || record.entity.nil?
  end

  def dynamic?
    show?
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

  def configure_grids?
    update?
  end
end
