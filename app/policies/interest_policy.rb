class InterestPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where("interest_entity_id=? or entity_id=?", user.entity_id, user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def owner?
    user.entity_id == record.interest_entity_id ||
      allow_external?(:read)
  end

  def show?
    user.has_cached_role?(:super) ||
      (user.entity_id == record.interest_entity_id) ||
      (user.entity_id == record.entity_id) ||
      sale_policy.owner? ||
      owner?
  end

  def short_list?
    user.has_cached_role?(:approver) && (user.entity_id == record.entity_id)
  end

  def unscramble?
    (record.escrow_deposited? && user.entity_id == record.entity_id) || # Escrow is deposited
      user.entity_id == record.interest_entity_id || # Interest is by this entity
      record.secondary_sale.buyer?(record.user) # Is a seller added by the startup for this sale
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

  def matched_offers?
    create? ||
      sale_policy.owner? ||
      owner?
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

  def allocation_form?
    sale_policy.update?
  end

  def allocate?
    sale_policy.update?
  end

  def sale_policy
    sale_policy ||= SecondarySalePolicy.new(user, record.secondary_sale)
    sale_policy
  end
end
