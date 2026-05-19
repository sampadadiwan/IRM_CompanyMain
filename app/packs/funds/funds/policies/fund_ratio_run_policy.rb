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

  def show?
    permissioned_employee?
  end
end
