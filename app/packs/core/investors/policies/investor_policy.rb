# InvestorPolicy defines access control for Investor records.
#
# Access Overview:
# 1. Company Admins: Full access to all investors within their entity.
# 2. Employees: Access depends on 'enable_investors' flag and specific permissions.
#    - Global Read: If they have :investor_read extended permission, they see all entity investors.
#    - Granular Access: Otherwise, they only see investors they are specifically assigned to.
# 3. Support: Has specific permissions bypassing standard employee checks.
#
class InvestorPolicy < ApplicationPolicy
  # Scope defines which Investor records a user can view in lists/searches.
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) || (user.enable_investors && user.get_extended_permissions.set?(:investor_read))
        # Company admins can see all investors belonging to their entity. Employees with the :investor_read permission can see all investors in the entity.
        scope.where(entity_id: user.entity_id)
      else
        # Other users only see investors they have been explicitly granted access to.
        scope.for_employee(user)
      end
    end
  end

  # Permission to list investors. Requires the 'enable_investors' feature flag.
  def index?
    user.enable_investors
  end

  def analytics?
    index?
  end

  # Permission to search investors. Same as index.
  def search?
    index?
  end

  # Permission to view a specific investor record.
  # Allowed if:
  # - 'enable_investors' is true AND
  # - (User belongs to the same entity as the investor OR has :investor_read permission)
  def show?
    user.enable_investors && (user.entity_id == record.investor_entity_id || specific_permissions?(:investor_read))
  end

  # Permission to view the capitalization table for an investor.
  # Requires 'show?' permission, 'enable_investments' flag, and the investor must be a 'Portfolio Company'.
  def cap_table?
    show? && user.enable_investments && record.category == "Portfolio Company"
  end

  # Permission to view the investor dashboard. Same as show.
  def dashboard?
    show?
  end

  # Permission to view agent report details. Same as show.
  def report_detail?
    show?
  end

  # Permission to generate reports. Requires update permissions.
  def generate_reports?
    update?
  end

  # Permission to view portfolio investment reports for this investor. Requires update permissions.
  def portfolio_investments_report?
    update?
  end

  # Permission to view all portfolio investment reports. Restricted to Company Admins.
  def portfolio_investments_report_all?
    index? && user.has_cached_role?(:company_admin)
  end

  def refresh_portfolio_table?
    index? # Any user who can view the index can refresh the portfolio table
  end

  # Permission to create new investors. Requires :investor_create (or custom) permission.
  def create?(emp_perm = :investor_create)
    specific_permissions?(emp_perm)
  end

  def new?
    create?
  end

  # Permission to update an investor. Requires :investor_update (or custom) permission.
  def update?(emp_perm = :investor_update)
    specific_permissions?(emp_perm)
  end

  def merge?
    update?
  end

  def edit?
    update?
  end

  # Permission to delete an investor. Requires :investor_destroy permission.
  def destroy?
    specific_permissions?(:investor_destroy)
  end

  # Permission to bulk upload investors.
  # Checks 'enable_investors' flag and standard CRUD permissions (Company Admin or Employee with create perm).
  def upload?
    user.enable_investors && company_admin_or_emp_crud?(user, Investor.new, :create)
  end

  # Helper to check for specific employee permissions or support role.
  # Checks both extended permissions (e.g., :investor_read) and standard permissions (e.g., :read).
  def specific_permissions?(perm = nil)
    (user.enable_investors &&
      (extended_permissioned_employee?(perm) || permissioned_employee?(perm.to_s.gsub("investor_", "").to_sym))) ||
      support?
  end
end
