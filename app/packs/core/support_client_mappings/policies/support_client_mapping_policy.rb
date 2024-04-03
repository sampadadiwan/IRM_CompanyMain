class SupportClientMappingPolicy < ApplicationPolicy
  def index?
    super_user?
  end

  def show?
    super_user?
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
    create?
  end
end
