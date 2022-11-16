class FundBasePolicy < ApplicationPolicy
  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
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
      false
    end
  end

  def permissioned_advisor?(perm = nil)
    # binding.pry

    if user.entity_id != record.entity_id && user.curr_role == "advisor"
      fund_id = record.instance_of?(Fund) ? record.id : record.fund_id
      @fund ||= Fund.for_advisor(user).includes(:access_rights).where("funds.id=?", fund_id).first
      if perm
        @fund.present? && @fund.access_rights[0].permissions.set?(perm)
      else
        @fund.present?
      end
    else
      false
    end
  end

  # This must always be called after permissioned_advisor?
  def permissioned_investor?
    if user.entity_id == record.entity_id
      false
    else
      @pi_record ||= record.class.for_investor(user).where("#{record.class.table_name}.id=?", record.id)
      @pi_record.present?
    end
  end

  def create?
    (user.entity_id == record.entity_id && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create) ||
      permissioned_advisor?(:create)
  end
end
