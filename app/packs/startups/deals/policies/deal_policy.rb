class DealPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif %w[startup fund_manager].include? user.curr_role
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
      end
    end
  end

  def index?
    user.enable_deals
  end

  def show?
    (user.entity_id == record.entity_id && user.enable_deals) ||
      permissioned_advisor?
  end

  def show_detail_tabs?
    user.entity_id == record.entity_id
  end

  def create?
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id && user.enable_deals)
  end

  def new?
    create?
  end

  def update?
    create? ||
      permissioned_advisor?(:update)
  end

  def start_deal?
    update?
  end

  def recreate_activities?
    start_deal?
  end

  def edit?
    create?
  end

  def destroy?
    create? ||
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
end
