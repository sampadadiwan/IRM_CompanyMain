require "administrate/base_dashboard"

class DocumentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    entity: Field::BelongsTo.with_options(
      searchable: true,
      searchable_fields: ['name']
    ),
    access_rights: Field::HasMany,
    folder: Field::BelongsTo.with_options(
      searchable: true,
      searchable_fields: ['name']
    ),
    rich_text_text: RichTextAreaField,
    id: Field::Number,
    file: Field::Shrine,
    name: ObfuscatedField,
    text: Field::String,
    tag_list: Field::String,
    download: Field::BooleanEmoji,
    printing: Field::BooleanEmoji,
    signature_enabled: Field::BooleanEmoji,
    signed_by_accept: Field::BooleanEmoji,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    name
    download
    printing
    signature_enabled
    signed_by_accept
    tag_list
    folder
    entity
    created_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    entity
    folder
    rich_text_text
    id
    name
    download
    printing
    signature_enabled
    signed_by_accept
    tag_list
    file
    created_at
    updated_at
    access_rights

  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    download
    printing
    signature_enabled
    signed_by_accept
    tag_list
    rich_text_text
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

  # Overwrite this method to customize how documents are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(document)
    document.name
  end
end
