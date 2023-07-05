class IoBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && ["Investment Fund", "Group Company"].include?(user.entity_type)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee) && ["Investment Fund", "Group Company"].include?(user.entity_type)
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def permissioned_employee?(perm = nil)
    if belongs_to_entity?(user, record)
      if user.has_cached_role?(:company_admin)
        true
      else
        investment_opportunity_id = record.instance_of?(InvestmentOpportunity) ? record.id : record.investment_opportunity_id
        @investment_opportunity ||= InvestmentOpportunity.for_employee(user).includes(:access_rights).where("investment_opportunities.id=?", investment_opportunity_id).first
        if perm
          @investment_opportunity.present? && @investment_opportunity.access_rights[0].permissions.set?(perm)
        else
          @investment_opportunity.present?
        end
      end
    else
      super_user?
    end
  end

  def permissioned_investor?
    if belongs_to_entity?(user, record)
      false
    else
      @pi_record ||= record.class.for_investor(user).where("#{record.class.table_name}.id=?", record.id)
      @pi_record.present?
    end
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create)
  end
end
