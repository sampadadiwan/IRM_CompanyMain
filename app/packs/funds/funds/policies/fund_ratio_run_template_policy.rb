# Any entity employee can view and trigger templates.
# Only the creator or a company_admin can mutate (create/edit/destroy).
class FundRatioRunTemplatePolicy < FundBasePolicy
  # FundBasePolicy::Scope calls model-level scopes (for_rm, for_company_admin, etc.)
  # that exist on Fund but not here. Templates are purely entity-scoped, so we
  # resolve by entity_id and role without those model-specific helpers.
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "investor"
        # Investors have no reason to manage run templates.
        scope.none
      else
        # All employees (rm, company_admin, employee) see their entity's templates.
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  # Trigger actions are available to any employee — they only enqueue jobs,
  # they don't mutate the template record itself.
  # Avoids permissioned_employee? because that calls belongs_to_entity?(user, record),
  # which fails when record is the class (collection-level authorize calls).
  # Entity scoping is already enforced by Scope#resolve.
  def trigger?
    user.enable_funds && !user.curr_role_investor?
  end

  def new?
    create?
  end

  def create?
    permissioned_employee?(:create)
  end

  def edit?
    update?
  end

  def update?
    # Only the creator or a company_admin can change the template configuration.
    permissioned_employee?(:update) &&
      (record.user_id == user.id || user.has_cached_role?(:company_admin))
  end

  def destroy?
    update?
  end
end
