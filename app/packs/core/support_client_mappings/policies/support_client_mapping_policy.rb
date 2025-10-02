class SupportClientMappingPolicy < ApplicationPolicy
  def switch?
    show? && record.enabled? && record.status != 'Switched' && record.entity.enable_support
  end

  def revert?
    show? && record.enabled? && record.status == 'Switched'
  end

  class Scope < Scope
    def resolve
      if user.super?
        scope.all
      else
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    true
  end

  def show?
    super_user? || (record.user_id == user.id && record.enabled?)
  end

  def create?
    super_user?
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
