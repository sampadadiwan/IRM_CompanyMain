class FundBasePolicy < ApplicationPolicy
  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
      if user.has_cached_role?(:company_admin)
        true
      else
        @emp_record = record.class.for_employee(user).where("#{record.class.table_name}.id=?", record.id).first
        if perm
          @emp_record.access_rights[0].permissions.set?(perm)
        else
          @emp_record.present?
        end
      end
    else
      false
    end
  end

  def permissioned_advisor?(perm = nil)
    if user.entity_id != record.entity_id && user.curr_role == "advisor"
      @pa_record ||= record.class.for_advisor(user).where("#{record.class.table_name}.id=?", record.id).first
      if perm
        @pa_record.access_rights[0].permissions.set?(perm)
      else
        @pa_record.present?
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
end
