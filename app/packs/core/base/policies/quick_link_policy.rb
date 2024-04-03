class QuickLinkPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if support?
        scope.all
      else
        scope.where(entity_id: [user.entity_id, nil])
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
    support? || belongs_to_entity?(user, record)
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
