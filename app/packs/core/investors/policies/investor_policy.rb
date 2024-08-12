class InvestorPolicy < ApplicationPolicy
  def index?
    user.enable_investors
  end

  def search?
    index?
  end

  def show?
    user.enable_investors &&
      ((belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :read)) || user.entity_id == record.investor_entity_id || permissioned_employee?)
  end

  def create?(emp_perm = :create)
    user.enable_investors && belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, emp_perm)
  end

  def new?
    create?
  end

  def update?(emp_perm = :update)
    create?(emp_perm) || support?
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

  def upload?
    user.enable_investors && company_admin_or_emp_crud?(user, Investor.new, :create)
  end

  def permissioned_employee?(perm = nil)
    if belongs_to_entity?(user, record)
      if user.has_cached_role?(:company_admin)
        true
      else
        @investor ||= Investor.for_employee(user).includes(:investor_access_rights).where("investors.id=?", record.id).first
        if perm
          @investor.present? && @investor.investor_access_rights[0].permissions.set?(perm)
        else
          @investor.present?
        end
      end
    else
      support?
    end
  end
end
