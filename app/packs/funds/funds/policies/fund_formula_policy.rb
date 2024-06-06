class FundFormulaPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:support)
        scope.all
      else
        super
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || support?
  end

  def create?
    support? # || (belongs_to_entity?(user, record) && record.fund.editable_formulas)
  end

  def new?
    create?
  end

  def update?
    support? || belongs_to_entity?(user, record.fund)
  end

  def enable_formulas?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
