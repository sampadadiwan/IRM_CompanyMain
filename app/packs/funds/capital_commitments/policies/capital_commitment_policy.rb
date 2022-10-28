class CapitalCommitmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:fund_manager)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:advisor)
        scope.for_advisor(user)
      else
        scope.joins(:investor).where('investors.investor_entity_id': user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) ||
      (user.entity_id == record.investor.investor_entity_id) ||
      record.fund.advisor?(user)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def generate_documentation?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
