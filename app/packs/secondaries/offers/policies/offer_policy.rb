class OfferPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  delegate :create?, :show?, :new?, :update?, :edit?, :destroy?, :approve?, :accept_spa?, :generate_docs?, :bulk_actions?, :accept_spa, :matched_interests?, to: :specific_policy
end
