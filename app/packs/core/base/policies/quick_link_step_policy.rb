class QuickLinkStepPolicy < ApplicationPolicy
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
