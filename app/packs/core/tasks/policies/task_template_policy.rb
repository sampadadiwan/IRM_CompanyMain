class TaskTemplatePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.support?
        # Support user
      end
      scope.all
    end
  end

  def index?
    true
  end

  def generate?
    true
  end

  def show?
    true # support?
  end

  def create?
    true # support?
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def completed?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
