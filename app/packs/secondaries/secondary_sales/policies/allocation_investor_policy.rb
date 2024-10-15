class AllocationPolicy < SaleBasePolicy
  def bulk_actions?
    false
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    Pundit.policy!(user, record.offer).permissioned_investor?(:seller) ||
      Pundit.policy!(user, record.interest).permissioned_investor?(:buyer)
  end

  def create?
    false
  end

  def generate_docs?
    false
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
end
