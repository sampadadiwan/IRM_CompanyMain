class SecondarySaleRmPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def offer?
    record.active? && show?
  end

  def owner?
    false
  end

  def offers?
    offer?
  end

  def interests?
    show_interest?
  end

  def payments?
    false
  end

  def show_interest?
    record.active? && show? && record.manage_offers
  end

  def see_private_docs?
    show? &&
      (InterestPolicy::Scope.new(user, Interest).resolve.short_listed.exists?(secondary_sale_id: record.id) ||
      OfferPolicy::Scope.new(user, Offer).resolve.approved.exists?(secondary_sale_id: record.id))
  end

  def show?
    permissioned_rm?
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
    record.active
  end

  def send_notification?
    show?
  end

  def notify_allocations?
    show?
  end

  def download?
    show?
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
    show?
  end

  def edit?
    false
  end

  def destroy?
    false
  end

  def buyer?
    true
  end

  def seller?
    true
  end

  def import_offers?
    true
  end

  def import_interests?
    true
  end

  def import?
    true
  end
end
