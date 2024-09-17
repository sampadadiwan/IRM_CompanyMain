class InvestorPolicy < ApplicationPolicy
  def index?
    user.enable_investors
  end

  def search?
    index?
  end

  def show?
    user.entity_id == record.investor_entity_id || permissioned_employee?(:investor_read)
  end

  def create?(emp_perm = :investor_create)
    permissioned_employee?(emp_perm)
  end

  def new?
    create?
  end

  def update?(emp_perm = :investor_update)
    create?(emp_perm)
  end

  def merge?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?(:investor_destroy)
  end

  def upload?
    user.enable_investors && company_admin_or_emp_crud?(user, Investor.new, :create)
  end

  def permissioned_employee?(perm = nil)
    extended_permissioned_employee?(perm) || support?
  end
end
