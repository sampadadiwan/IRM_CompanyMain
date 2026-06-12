# Provides named context values for Valuation rules.
#
# The condition_tree references these as "context.prev_valuation_cents" etc.
# Add new keys here when new rule conditions require additional data
# (e.g. fund NAV, rolling averages) without touching the DB schema.
class ValuationRuleContextProvider
  # @param record [Valuation] The record being validated (unsaved changes applied)
  # @param entity [Entity]    The tenant (unused here but part of the standard interface)
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    prev = find_previous_valuation(record)

    {
      # Most recent per-share value (in cents) for the same instrument before this valuation's date.
      # Referenced in condition_tree as "context.prev_per_share_value_cents".
      prev_per_share_value_cents: prev&.per_share_value_cents,

      # Date of that previous valuation — useful for date-gap rules
      prev_valuation_date: prev&.valuation_date
    }
  end

  private

  # Returns the most recent Valuation for the same investment_instrument
  # whose valuation_date is strictly before the current record's date.
  # Scoped to the same owner (portfolio company) when one is set.
  def find_previous_valuation(record)
    return nil unless record.investment_instrument_id.present? && record.valuation_date.present?

    scope = Valuation.unscoped
                     .where(investment_instrument_id: record.investment_instrument_id)
                     .where(valuation_date: ...record.valuation_date)

    # Narrow to same owner when the valuation is owner-scoped
    scope = scope.where(owner_type: record.owner_type, owner_id: record.owner_id) if record.owner_id.present?

    # Exclude self when validating an update so we don't compare a record to itself
    scope = scope.where.not(id: record.id) if record.persisted?

    scope.order(valuation_date: :desc).first
  end
end
