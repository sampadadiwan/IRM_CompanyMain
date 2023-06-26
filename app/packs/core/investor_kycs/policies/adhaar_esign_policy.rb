class AdhaarEsignPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def create?
    false
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

  # Only users who are part of this eSign can complete it
  def completed?
    record.owner.esigns.where(user_id: user.id).present?
  end
end
