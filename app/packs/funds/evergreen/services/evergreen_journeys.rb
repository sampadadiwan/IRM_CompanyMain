# Seeds the evergreen journey templates (one per dealing date, one per order) and their catch-all
# auto-assignment rules for an entity. Idempotent — JourneySetup finds templates by system_key and
# never adds a rule next to an existing one.
class EvergreenJourneys
  SETUPS = %w[DealingDateJourneySetup DealingOrderJourneySetup].freeze

  def self.seed(entity)
    SETUPS.each do |name|
      klass = name.safe_constantize
      klass&.call(entity:, execute: true)
    end
  end
end
