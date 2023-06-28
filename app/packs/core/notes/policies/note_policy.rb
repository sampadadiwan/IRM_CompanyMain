class NotePolicy < ApplicationPolicy
  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      belongs_to_entity?(user, record)
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
