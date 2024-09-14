class AmlReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %i[employee].include? user.curr_role.to_sym
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    user.entity.entity_setting.aml_enabled?
  end

  # investor can see investor kyc but not aml report
  def show?
    index? && permissioned_employee?
  end

  def create?
    false
  end

  def new?
    create?
  end

  def generate_new?
    index? && permissioned_employee?(:investor_kyc_update)
  end

  def toggle_approved?
    show?
  end

  def update?
    false
  end

  def edit?
    false
  end

  def destroy?
    false
  end

  def aml_enabled
    user.entity.entity_setting.aml_enabled?
  end

  def permissioned_employee?(perm = nil)
    InvestorKycPolicy.new(user, record).permissioned_employee?(perm)
  end
end
