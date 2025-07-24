class SecondarySalePolicy < SaleBasePolicy
  delegate :offer?, :owner?, :offers?, :interests?, :payments?, :show_interest?, :see_private_docs?, :show?, :report?, :create?, :new?, :update?, :generate_spa?, :send_notification?, :notify_allocations?, :download?, :allocate?, :approve_offers?, :short_list_interests?, :view_allocations?, :edit?, :destroy?, :buyer?, :seller?, to: :specific_policy

  def index?
    user.enable_secondary_sale
  end

  def import_offers?
    if specific_policy.respond_to?(:import_offers?)
      specific_policy.import_offers?
    else
      false
    end
  end

  def import_interests?
    if specific_policy.respond_to?(:import_interests?)
      specific_policy.import_interests?
    else
      false
    end
  end

  def import?
    if specific_policy.respond_to?(:import?)
      specific_policy.import?
    else
      false
    end
  end
end
