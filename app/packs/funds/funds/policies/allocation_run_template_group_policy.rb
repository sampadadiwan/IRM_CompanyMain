# Decision 4: a group may be viewed, changed or run by company admins, or by employees
# permissioned on every fund in the group. The per-fund check is repeated on each template
# inside the pre-flight, so this policy gates the screens and the trigger only.
class AllocationRunTemplateGroupPolicy < ApplicationPolicy
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

  def index?
    user.enable_funds && !user.curr_role_investor?
  end

  def show?
    all_funds_permitted?
  end

  def new?
    index?
  end

  # On create the group has its templates assigned but is unsaved; check those funds.
  def create?
    all_funds_permitted?
  end

  def edit?
    update?
  end

  def update?
    all_funds_permitted?
  end

  def destroy?
    all_funds_permitted?
  end

  def preflight?
    run?
  end

  def run?
    all_funds_permitted?
  end

  private

  def all_funds_permitted?
    return false unless index?
    return false unless belongs_to_entity?(user, record)
    return true if user.has_cached_role?(:company_admin)

    funds = record.items.filter_map { |i| i.allocation_run_template&.fund }.uniq
    funds.any? && funds.all? { |fund| FundPolicy.new(user, fund).allocate? }
  end
end
