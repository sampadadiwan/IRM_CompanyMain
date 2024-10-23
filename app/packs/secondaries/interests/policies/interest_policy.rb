class InterestPolicy < SaleBasePolicy
  delegate :show?, :create?, :new?, :update?, :edit?, :destroy?, :generate_docs?, :short_list?, :matched_offers?, :accept_spa?, :matched_offer?, :owner?, :send_email_to_change?, to: :specific_policy

  def index?
    user.enable_secondary_sale
  end
end
