class InvestorPolicy < ApplicationPolicy
  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      ((belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :read)) || user.entity_id == record.investor_entity_id || super_user?)
  end

  def create?(emp_perm = :create)
    user.enable_investors && belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, emp_perm)
  end

  def new?
    create?
  end

  def update?(emp_perm = :update)
    create?(emp_perm) || super_user?
  end

  def merge?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?(:destroy)
  end
end
