class DealPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:rm)
        scope.for_rm(user)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      elsif %w[employee].include?(user.curr_role) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif %w[employee].include? user.curr_role
        scope.for_employee(user)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_deals
  end

  def show?
    (permissioned_employee? || permissioned_investor?) && user.enable_deals
  end

  def show_detail_tabs?
    show? && belongs_to_entity?(user, record)
  end

  def create?
    user.enable_deals
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    create?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
