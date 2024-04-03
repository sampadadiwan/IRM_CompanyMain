class FundBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.has_cached_role?(:company_admin) && (user.entity.is_fund? || user.entity.is_group_company?)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee) && (user.entity.is_fund? || user.entity.is_group_company?)
        scope.for_employee(user)
      else
        scope.none
      end
    end
  end

  def permissioned_employee?(perm = nil)
    if belongs_to_entity?(user, record)
      if user.has_cached_role?(:company_admin)
        true
      else
        fund_id = record.instance_of?(Fund) ? record.id : record.fund_id
        @fund ||= Fund.for_employee(user).includes(:access_rights).where("funds.id=?", fund_id).first
        if perm
          @fund.present? && @fund.access_rights[0].permissions.set?(perm)
        else
          @fund.present?
        end
      end
    else
      support?
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
