class AllocationRmPolicy < SaleBasePolicy
  def bulk_actions?
    user.enable_secondary_sale && permissioned_rm?(:update)
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    permissioned_rm?
  end

  def create?
    false
  end

  def generate_docs?
    update?
  end

  def accept_spa?
    show?
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def permissioned_rm?(metadata = "none", owner: nil)
    OfferPolicy.new(user, record.offer).permissioned_rm?(metadata, owner:) ||
      InterestPolicy.new(user, record.interest).permissioned_rm?(metadata, owner:)
  end
end
