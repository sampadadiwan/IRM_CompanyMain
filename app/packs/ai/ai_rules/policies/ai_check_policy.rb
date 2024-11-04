class AiCheckPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_compliance
  end

  def show?
    user.enable_compliance &&
      belongs_to_entity?(user, record)
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
