class FolderPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    if user.investor_advisor?
      belongs_to_entity?(user, record) && record.owner && Pundit.policy(user, record.owner).show?
    else
      belongs_to_entity?(user, record) || super_user?
    end
  end

  def download?
    create? && user.has_cached_role?(:company_admin)
  end

  def create?
    belongs_to_entity?(user, record)
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
    false
  end
end
