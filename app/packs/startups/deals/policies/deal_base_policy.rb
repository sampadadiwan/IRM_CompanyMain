class DealBasePolicy < ApplicationPolicy
  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
      if user.has_cached_role?(:company_admin)
        true
      else
        deal_id = record.instance_of?(Deal) ? record.id : record.deal_id
        @deal ||= Deal.for_employee(user).includes(:access_rights).where("deals.id=?", deal_id).first
        if perm
          @deal.present? && @deal.access_rights[0].permissions.set?(perm)
        else
          @deal.present?
        end
      end
    else
      false
    end
  end

  def permissioned_advisor?(perm = nil)
    # binding.pry

    if user.entity_id != record.entity_id && user.curr_role == "advisor"
      deal_id = record.instance_of?(Deal) ? record.id : record.deal_id
      @deal ||= Deal.for_advisor(user).includes(:access_rights).where("deals.id=?", deal_id).first
      if perm
        @deal.present? && @deal.access_rights[0].permissions.set?(perm)
      else
        @deal.present?
      end
    else
      false
    end
  end
end
