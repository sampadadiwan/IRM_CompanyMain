class SaleBasePolicy < ApplicationPolicy
  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
      if user.has_cached_role?(:company_admin)
        true
      else
        secondary_sale_id = record.instance_of?(SecondarySale) ? record.id : record.secondary_sale_id
        @secondary_sale ||= SecondarySale.for_employee(user).includes(:access_rights).where("secondary_sales.id=?", secondary_sale_id).first
        if perm
          @secondary_sale.present? && @secondary_sale.access_rights[0].permissions.set?(perm)
        else
          @secondary_sale.present?
        end
      end
    else
      false
    end
  end

  def permissioned_advisor?(perm = nil)
    # binding.pry

    if user.entity_id != record.entity_id && user.curr_role == "advisor"
      secondary_sale_id = record.instance_of?(SecondarySale) ? record.id : record.secondary_sale_id
      @secondary_sale ||= SecondarySale.for_advisor(user).includes(:access_rights).where("secondary_sales.id=?", secondary_sale_id).first
      if perm
        @secondary_sale.present? && @secondary_sale.access_rights[0].permissions.set?(perm)
      else
        @secondary_sale.present?
      end
    else
      false
    end
  end

  # This must always be called after permissioned_advisor?
  def permissioned_investor?(metadata = "none")
    @pi_record ||= {}
    @pi_record[metadata] ||= if metadata == "none"
                               record.class.for_investor(user).where("#{record.class.table_name}.id=?", record.id)
                             else
                               record.class.for_investor(user).where("#{record.class.table_name}.id=?", record.id).where("access_rights.metadata=?", metadata)
                             end
    @pi_record[metadata].present?
  end

  def create?
    (user.entity_id == record.entity_id && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create) ||
      permissioned_advisor?(:create)
  end
end
