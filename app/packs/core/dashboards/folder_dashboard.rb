require "administrate/base_dashboard"

class FolderDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    parent: Field::BelongsTo,
    entity: Field::BelongsTo,
    documents: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    parent_id: Field::Number,
    full_path: Field::Text,
    level: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    documents_count: Field::Number
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    parent
    entity
    full_path
    level
    id
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    parent
    entity
    id
    name
    parent_id
    full_path
    level
    created_at
    updated_at
    documents_count
    documents
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    parent
    entity
    name
    parent_id
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an options to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how folders are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(folder)
    folder.full_path
  end
end
