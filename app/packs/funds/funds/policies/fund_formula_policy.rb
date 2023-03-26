class FundFormulaPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id)
  end

  def create?
    (user.entity_id == record.entity_id) && record.fund.editable_formulas
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
