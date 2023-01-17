class DealPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif %w[employee].include?(user.curr_role) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif %w[employee].include? user.curr_role
        scope.for_employee(user)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_deals
  end

  def show?
    (permissioned_employee? && user.enable_deals) ||
      permissioned_advisor?
  end

  def show_detail_tabs?
    user.entity_id == record.entity_id
  end

  def create?
    permissioned_employee?(:create) && user.enable_deals
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def edit?
    create?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end

  def permissioned_advisor?(perm = nil)
    # binding.pry

    if user.entity_id != record.entity_id && user.curr_role == "advisor"
      deal_id = record.instance_of?(Deal) ? record.id : record.deal_id
      @deal ||= Deal.for_advisor(user).includes(:access_rights).where("deals.id=?", deal_id).first
      if perm
        @deal.present? && @deal.access_rights[0].permissions.set?(perm)
      else
        @deal.present?
      end
    else
      false
    end
  end

  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
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
