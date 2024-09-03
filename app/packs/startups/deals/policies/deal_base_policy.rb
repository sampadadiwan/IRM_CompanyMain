class DealBasePolicy < ApplicationPolicy
  attr_accessor :deal_investor

  def permissioned_employee?(perm = nil)
    deal_id = record.instance_of?(Deal) ? record.id : record.deal_id
    super(deal_id, "Deal", perm)
  end
end
