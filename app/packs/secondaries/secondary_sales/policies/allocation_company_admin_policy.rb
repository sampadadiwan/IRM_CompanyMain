class AllocationCompanyAdminPolicy < SaleBasePolicy
  # H6 step 2 — class-safe: WithBulkActions authorizes the class (Allocation), where there is no sale to
  # check access on (the record check used to raise on a class). On the class: secondaries enabled; on a
  # record (the job's per-row check): plus update access on the sale. Tests H6-H3, H6-S1…S3, H6-SH —
  # features/security/bulk_actions_authorization.feature
  def bulk_actions?
    return user.enable_secondary_sale if record.instance_of?(Class)

    user.enable_secondary_sale && permissioned_employee?(:update)
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    permissioned_employee?
  end

  def create?
    permissioned_employee?(:create)
  end

  def generate_docs?
    update?
  end

  def accept_spa?
    false
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  # Verify / unverify is an edit of the allocation, as in the bulk Verify action (AllocationsBulkActionJob)
  def verify?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) && !record.verified?
  end
end
