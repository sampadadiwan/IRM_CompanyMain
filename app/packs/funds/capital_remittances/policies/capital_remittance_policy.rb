class CapitalRemittancePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:fund_manager) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:fund_manager)
        scope.for_employee(user)
      elsif user.has_cached_role?(:advisor)
        scope.for_advisor(user)
      else
        scope.joins(:investor, :capital_call).where('capital_calls.approved = ? and investors.investor_entity_id = ?', true, user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def permissioned_employee?
    user.entity_id == record.entity_id &&
      CapitalRemittance.for_employee(user).where("capital_remittances.id=?", record.id).present?
  end

  def show?
    (user.entity_id == record.entity_id && user.has_cached_role?(:company_admin)) ||
      permissioned_employee? ||
      (user.entity_id == record.investor.investor_entity_id) ||
      record.fund.advisor?(user)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def verify?
    create?
  end

  def update?
    create? ||
      (user.entity_id == record.investor.investor_entity_id)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
