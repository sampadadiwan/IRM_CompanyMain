class KanbanCardIndex < Chewy::Index
  SEARCH_FIELDS = %i[title tags notes info_field].freeze

  index_scope KanbanCard.includes(:kanban_board, :kanban_column, :entity)
  field :title
  field :info_field
  field :entity_id
  field :tags
  field :notes, value: ->(kc) { kc.notes.present? ? ActionText::Content.new(kc.notes).to_plain_text : nil }
end
