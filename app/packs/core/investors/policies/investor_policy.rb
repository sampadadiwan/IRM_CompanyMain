class InvestorPolicy < ApplicationPolicy
  class Scope < Scope
    # rubocop:disable Lint/DuplicateBranch
    def resolve
      if user.has_cached_role?(:company_admin)
        # Company admin can see all investors
        scope.where(entity_id: user.entity_id)
      elsif user.enable_investors && user.get_extended_permissions.set?(:investor_read)
        # Employee who has permission to read investors can see all investors
        scope.where(entity_id: user.entity_id)
      else
        # Can see investors for which the user has been granted specific access
        # scope.for_employee(user)
        scope.none
      end
    end
    # rubocop:enable Lint/DuplicateBranch
  end

  def index?
    user.enable_investors
  end

  def search?
    index?
  end

  def show?
    user.entity_id == record.investor_entity_id || permissioned_employee?(:investor_read)
  end

  def cap_table?
    show? && user.enable_investments && record.category == "Portfolio Company"
  end

  def dashboard?
    show?
  end

  def generate_reports?
    update?
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
