class KpiChartSettingPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end

  def index?
    true
  end

  def show?
    record.user_id == user.id
  end

  def create?
    true
  end

  def update?
    show?
  end

  def destroy?
    show?
  end
end
