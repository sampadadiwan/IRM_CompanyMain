class InterestPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where("interest_entity_id=? or offer_entity_id=?", user.entity_id, user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    user.has_cached_role?(:super) || (user.entity_id == record.interest_entity_id) ||
      (user.entity_id == record.offer_entity_id)
  end

  def short_list?
    (user.entity_id == record.offer_entity_id)
  end

  def unscramble?
    (record.escrow_deposited? && user.entity_id == record.offer_entity_id) || user.entity_id == record.interest_entity_id
  end

  def create?
    user.id == record.user_id
  end

  def new?
    user.id == record.user_id
  end

  def update?
    create? && !record.finalized
  end

  def edit?
    update?
  end

  def finalize?
    update? && record.short_listed
  end

  def destroy?
    update?
  end
end
