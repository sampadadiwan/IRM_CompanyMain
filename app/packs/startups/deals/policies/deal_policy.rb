class DealPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
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
    permissioned_employee? && user.enable_deals
  end

  def kanban?
    show? && belongs_to_entity?(user, record)
  end

  def show_detail_tabs?
    belongs_to_entity?(user, record)
  end

  def create?
    permissioned_employee?(:create) && user.enable_deals
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

  def permissioned_employee?(perm = nil)
    if belongs_to_entity?(user, record)
      if user.has_cached_role?(:company_admin)
        true
      else
        deal_id = record.instance_of?(Deal) ? record.id : record.deal_id
        @deal ||= Deal.for_employee(user).includes(:access_rights).where("deals.id=?", deal_id).first
        if perm
          @deal.present? && @deal.access_rights[0].permissions.set?(perm)
        else
          @deal.present?
        end
      end
    else
      false
    end
  end
end
