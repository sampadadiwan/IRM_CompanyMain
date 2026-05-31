# Read-only — any entity employee can view a run's input params.
class FundRatioRunPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  # Avoids permissioned_employee? because that calls belongs_to_entity?(user, record),
  # which fails when record is the class (collection-level authorize calls).
  # Entity scoping is enforced by Scope#resolve.
  def index?
    user.enable_funds && !user.curr_role_investor?
  end

  def show?
    permissioned_employee?
  end
end
