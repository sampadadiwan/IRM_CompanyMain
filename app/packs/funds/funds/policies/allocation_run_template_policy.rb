# Decision 4: company admins, or employees permissioned to run allocations on the template's
# fund, may view, define and change allocation run templates. Investors never see them.
class AllocationRunTemplatePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "investor"
        scope.none
      else
        # Every employee of the entity can list templates; per-fund rights gate the actions.
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.enable_funds && !user.curr_role_investor?
  end

  def show?
    fund_permitted?
  end

  # Class-level authorize for the new form; the fund is only known on create.
  def new?
    index?
  end

  def create?
    fund_permitted?
  end

  def edit?
    update?
  end

  def update?
    fund_permitted?
  end

  def destroy?
    fund_permitted?
  end

  # JSON lookup of the statement documents on a fund, used by the template form.
  def statement_documents?
    index?
  end

  private

  # The same right that lets a person run a manual allocation on the fund.
  def fund_permitted?
    return false unless index?
    return false unless belongs_to_entity?(user, record)
    # D: the fund is in one of the user's firms, checked before the company-admin shortcut
    return false unless parent_in_users_firms?(record.fund)
    return true if user.has_cached_role?(:company_admin)

    record.fund.present? && FundPolicy.new(user, record.fund).allocate?
  end
end
