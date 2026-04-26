class CommitmentAdjustmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[adjustment_type folio_id fund_name reason].freeze

  index_scope CommitmentAdjustment.includes(:capital_commitment, :fund)
  field :entity_id
  field :folio_id, value: ->(adjustment) { adjustment.capital_commitment&.folio_id }
  field :adjustment_type
  field :reason
  field :as_of, type: "date"
  field :fund_name, value: ->(adjustment) { adjustment.fund.name }
end
