class QuickLinkStepPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    record.quick_link.entity.nil? || belongs_to_entity?(user, record.quick_link)
  end

  def create?
    belongs_to_entity?(user, record.quick_link)
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
