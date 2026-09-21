# Incremental allocation and run check suggestions on the fund formulas page (FundFormulaOperation) are
# support-only: they rewrite formulas, overwrite stored starting values and add check formulas, the same
# class of change as creating formulas (FundFormulaPolicy#create?).
class FundFormulaOperationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.support?
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index? = support?
  def suggestions? = support?
  def show? = support?
  def create? = support?
  def apply? = support?
  def add_suggestions? = support?
  def download_suggestions? = support?
end
