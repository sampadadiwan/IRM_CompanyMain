class AllocationPolicy < SaleBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:rm)
        # Get all the investors covered by the RM
        rm_mappings = RmMapping.approved.where(rm_entity_id: user.entity_id)
        investor_ids = rm_mappings.pluck(:investor_id)
        Rails.logger.debug { "Investor ids: #{investor_ids}" }
        # Find all allocations where the RM is either the investor or the offer and interest are of investors covered by the RM
        scope.joins(:offer, :interest).where(offers: { investor_id: investor_ids }).or(scope.joins(:offer, :interest).where(interests: { investor_id: investor_ids }))
      elsif investor_side?
        own_side_allocations
      else
        super
      end
    end

    private

    # The users SaleBasePolicy::Scope lists through for_investor: the investor persona, and holding
    # users who are not also the company's own staff (that branch is checked first there).
    def investor_side?
      return true if user.curr_role == "investor"

      company_staff = ["Company", "Group Company"].include?(user.entity_type) &&
                      (user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee))
      user.curr_role == "holding" && !company_staff
    end

    # H11: an LP lists only the allocations of their own offers (as a seller) or their own interests
    # (as a buyer). Allocation.for_investor matched every allocation of every sale the LP had access
    # to, so a seller saw every other seller's and buyer's allocation. Reusing the offer and interest
    # scopes keeps the advisor and holding rules identical to the Offers / Interests tabs.
    # Tests H11-1, H11-X, H11-X2 — features/security/secondaries_isolation.feature
    def own_side_allocations
      # The ids the user's Offers and Interests lists show. Both scopes are DISTINCT, so drop any
      # ORDER BY first (MySQL refuses DISTINCT with an ORDER BY column outside the select list)
      offer_ids = OfferPolicy::Scope.new(user, Offer).resolve.unscope(:order).select(:id)
      interest_ids = InterestPolicy::Scope.new(user, Interest).resolve.unscope(:order).select(:id)
      # Seller rows or buyer rows: both for a user who is both
      scope.where(offer_id: offer_ids).or(scope.where(interest_id: interest_ids))
    end
  end

  delegate :bulk_actions?, :show?, :create?, :generate_docs?, :accept_spa?, :new?, :update?, :edit?, :destroy?, to: :specific_policy

  def index?
    user.enable_secondary_sale
  end
end
