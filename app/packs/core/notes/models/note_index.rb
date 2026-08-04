class NoteIndex < Chewy::Index
  SEARCH_FIELDS = %i[details entity_name user_full_name for_name].freeze

  index_scope Note.with_all_rich_text.includes(:owner, :entity, :user)
  field :owner_id
  field :details, value: ->(note) { note.details.body.to_html }
  field :tags
  field :entity_id
  field :entity_name, value: ->(note) { note.entity.name if note.entity }
  field :user_id
  field :user_full_name, value: ->(note) { note.user.full_name if note.user }
  # `for_name` mirrors the "For" column text (`note.to_s`) used in the notes table.
  field :for_name, value: ->(note) { note.to_s }
end
