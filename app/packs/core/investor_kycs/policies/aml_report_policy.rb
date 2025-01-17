class AmlReportPolicy < ApplicationPolicy
  def index?
    false
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
