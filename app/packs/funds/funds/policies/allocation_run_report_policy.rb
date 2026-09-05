# Who may run and read the allocation run checker. The same people who may run an allocation
# on the fund may check one — the report is a read of the fund's own ledger and says nothing a
# person with allocation rights cannot already see on the account entries screen.
class AllocationRunReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "investor"
        scope.none
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def show?
    fund_permitted?
  end

  # Running the checker writes an AllocationRunReport but changes nothing in the ledger.
  def create?
    fund_permitted?
  end

  private

  # The same right that lets a person run a manual allocation on the fund.
  def fund_permitted?
    return false unless user.enable_funds && !user.curr_role_investor?
    return false unless belongs_to_entity?(user, record)
    return true if user.has_cached_role?(:company_admin)

    record.fund.present? && FundPolicy.new(user, record.fund).allocate?
  end
end
