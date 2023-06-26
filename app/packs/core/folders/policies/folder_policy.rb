class FolderPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    user.entity_id == record.entity_id || super_user?
  end

  def download?
    create? && user.has_cached_role?(:company_admin)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    (create? || super_user?) && !record.system?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
