class HoldingAuditTrailIndex < Chewy::Index
  SEARCH_FIELDS = %i[action parent_id entity_name owner operation ref_type ref_id comments].freeze

  index_scope HoldingAuditTrail.includes(:entity)
  field :entity_name, value: ->(di) { di.entity.name if di.entity }
  field :action
  field :parent_id
  field :entity_id
  field :owner
  field :operation
  field :ref_type
  field :ref_id
  field :comments
end
