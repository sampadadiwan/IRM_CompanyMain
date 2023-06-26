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
    elsif user.entity_type == "Group Company"
      permissioned_parent_employee?(perm)
    else
      super_user?
    end
  end

  def permissioned_parent_employee?(perm = nil)
    if user.entity.child_ids.include?(record.entity_id)
      if user.has_cached_role?(:company_admin)
        true
      else
        fund_id = record.instance_of?(Fund) ? record.id : record.fund_id
        @fund ||= Fund.for_parent_company_employee(user).includes(:access_rights).where("funds.id=?", fund_id).first
        if perm
          @fund.present? && @fund.access_rights[0].permissions.set?(perm)
        else
          @fund.present?
        end
      end
    else
      super_user?
    end
  end

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
      permissioned_employee?(:create)
  end
end
