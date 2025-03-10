class NoteIndex < Chewy::Index
  SEARCH_FIELDS = %i[details investor_name entity_name user_name].freeze

  index_scope Note.with_all_rich_text.includes(:investor, :entity, :user)
  field :investor_name
  field :investor_id
  field :details, value: ->(note) { note.details.body.to_html }
  field :tags
  field :entity_id
  field :entity_name, value: ->(note) { note.entity.name if note.entity }
  field :user_id
  field :user_full_name, value: ->(note) { note.user.full_name if note.user }
  field :on, type: "date"
end
