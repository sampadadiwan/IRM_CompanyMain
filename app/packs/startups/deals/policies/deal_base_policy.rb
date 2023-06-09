class DealBasePolicy < ApplicationPolicy
  attr_accessor :deal_investor

  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
      if user.has_cached_role?(:company_admin)
        true
      else
        deal_investor_id = record.instance_of?(DealInvestor) ? record.id : record.deal_investor_id
        @deal_investor ||= DealInvestor.for_employee(user).includes(:access_rights).where("deal_investors.id=?", deal_investor_id).first
        if perm
          @deal_investor.present? && @deal_investor.access_rights[0].permissions.set?(perm)
        else
          @deal_investor.present?
        end
      end
    else
      false
    end
  end
end
