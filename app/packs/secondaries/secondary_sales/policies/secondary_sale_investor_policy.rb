class SecondarySaleInvestorPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def offer?
    record.active? && permissioned_investor?(:seller)
  end

  def owner?
    false
  end

  def offers?
    permissioned_investor?(:seller)
  end

  def interests?
    permissioned_investor?(:buyer)
  end

  def payments?
    false
  end

  def show_interest?
    record.active? && permissioned_investor?(:buyer)
  end

  def see_private_docs?
    show? &&
      (InterestPolicy::Scope.new(user, Interest).resolve.short_listed.exists?(secondary_sale_id: record.id) ||
      OfferPolicy::Scope.new(user, Offer).resolve.approved.exists?(secondary_sale_id: record.id))
  end

  def show?
    permissioned_investor?
  end

  def report?
    show?
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def generate_spa?
    owner?
  end

  def send_notification?
    owner?
  end

  def notify_allocations?
    owner?
  end

  def download?
    owner?
  end

  def allocate?
    false
  end

  def approve_offers?
    false
  end

  def short_list_interests?
    false
  end

  def view_allocations?
    true
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def buyer?
    permissioned_investor?(:buyer)
  end

  def seller?
    permissioned_investor?(:seller)
  end
end
