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
      else
        super
      end
    end
  end

  delegate :bulk_actions?, :show?, :create?, :generate_docs?, :accept_spa?, :new?, :update?, :edit?, :destroy?, to: :specific_policy

  def index?
    user.enable_secondary_sale
  end
end
