class FundReportPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    permissioned_employee? ||
      permissioned_investor? ||
      permissioned_advisor?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end
end
