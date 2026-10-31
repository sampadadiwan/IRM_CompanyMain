class AllocationRmPolicy < SaleBasePolicy
  # H6 step 2 — class-safe: WithBulkActions authorizes the class (Allocation), where there is no sale to
  # check access on (the record check used to raise on a class). On the class: secondaries enabled; on a
  # record (the job's per-row check): plus update access on the sale. Tests H6-H3, H6-S1…S3, H6-SH —
  # features/security/bulk_actions_authorization.feature
  def bulk_actions?
    return user.enable_secondary_sale if record.instance_of?(Class)

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

  # H19: an RM acts for a seller or buyer, never verifies an allocation
  def verify?
    false
  end

  def destroy?
    false
  end

  def permissioned_rm?(metadata = "none", owner: nil)
    OfferPolicy.new(user, record.offer).permissioned_rm?(metadata, owner:) ||
      InterestPolicy.new(user, record.interest).permissioned_rm?(metadata, owner:)
  end
end
