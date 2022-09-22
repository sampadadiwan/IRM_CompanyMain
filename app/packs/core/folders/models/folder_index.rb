class FolderIndex < Chewy::Index
  SEARCH_FIELDS = %i[name full_path entity_name].freeze

  index_scope Folder.includes(:entity, :parent)
  field :name
  field :full_path
  field :entity_id
  field :entity_name, value: ->(f) { f.entity.name if f.entity }
end
