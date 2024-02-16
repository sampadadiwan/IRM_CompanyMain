class FavoritePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(favoritor: user)
      end
    end
  end

  def index?
    true
  end

  def show?
    record.favoritor == user
  end

  def create?
    record.favoritor == user
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
