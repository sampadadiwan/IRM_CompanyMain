class DocumentIndex < Chewy::Index
  SEARCH_FIELDS = %i[name folder_name folder_full_path entity_name tag_list properties].freeze

  index_scope Document.includes(:entity, :folder)

  field :name
  field :tag_list
  field :entity_id
  field :entity_name, value: ->(doc) { doc.entity.name if doc.entity }
  field :folder_full_path
  field :folder_id
  field :properties, value: ->(doc) { doc.properties.to_json if doc.properties }
  field :folder_name, value: ->(doc) { doc.folder.name if doc.folder }
  field :folder_full_path, value: ->(doc) { doc.folder.full_path if doc.folder }
  field :created_at, type: "date"
end
