class SaleBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && ["Company", "Group Company"].include?(user.entity_type)
        scope.for_company_admin(user)
      elsif user.curr_role == 'employee' && ["Company", "Group Company"].include?(user.entity_type)
        scope.for_employee(user)
      elsif user.curr_role == 'holding'
        scope.for_investor(user).distinct
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
        secondary_sale_id = record.instance_of?(SecondarySale) ? record.id : record.secondary_sale_id
        @secondary_sale ||= SecondarySale.for_employee(user).includes(:access_rights).where("secondary_sales.id=?", secondary_sale_id).first
        if perm
          @secondary_sale.present? && @secondary_sale.access_rights[0].permissions.set?(perm)
        else
          @secondary_sale.present?
        end
      end
    else
      super_user?
    end
  end

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
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create)
  end
end
