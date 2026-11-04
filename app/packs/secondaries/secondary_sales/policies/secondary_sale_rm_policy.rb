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
    show?
  end

  def interests?
    show?
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

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  # H15: sale-wide SPA regeneration is the selling firm's job. Nothing in the UI links an RM to it
  # (per-record documents go through generate_docs), and `record.active` alone let an RM with no
  # access to the sale regenerate - and delete - every seller's SPA.
  # Tests H15-1, H15-X — features/security/secondaries_isolation.feature
  def generate_spa?
    false
  end

  def send_notification?
    show?
  end

  def notify_allocations?
    show?
  end

  # The full sale sheet holds every seller's and buyer's PAN, bank and address, so it is for the
  # sale's own firm only (as for LPs) - an RM sees their mapped clients on screen (security review 2026-10, C4 follow-up)
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

  # H15: RMs never upload offers (no button offers it to them)
  def import_offers?
    false
  end

  # H15: the "Upload Interests" button, on a live sale the RM can see. Was `true`, so an RM could
  # import interests into any sale, including other firms' and closed ones.
  # Tests H15-2, H15-H2, H15-X — features/security/secondaries_isolation.feature
  def import_interests?
    show? && record.active?
  end

  # H15: ImportUploadPolicy asks import? of the upload's owner; for an RM that is the interest upload
  def import?
    import_interests?
  end
end
