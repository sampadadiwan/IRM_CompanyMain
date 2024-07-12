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
    belongs_to_entity?(user, record)
  end

  # Only support can create / update formulas
  def create?
    support?
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record) || support?
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
