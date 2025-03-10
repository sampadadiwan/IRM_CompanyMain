class AmlReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:employee)
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    (user.entity.entity_setting.aml_enabled? && user.has_cached_role?(:employee)) || support?
  end

  def show?
    (record.entity.entity_setting.aml_enabled? && record.investor_kyc && Pundit.policy(user, record.investor_kyc).permissioned_employee?(:investor_kyc_read)) || support?
  end

  def new?
    create?
  end

  def create?
    false
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
