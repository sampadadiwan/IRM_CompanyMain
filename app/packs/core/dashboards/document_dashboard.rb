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
    e_signatures: Field::HasMany,
    folder: Field::BelongsTo.with_options(
      searchable: true,
      searchable_fields: ['name']
    ),
    rich_text_text: RichTextAreaField,
    id: Field::Number,
    file: Field::Shrine,
    name: Field::String,
    esign_status: Field::String,
    provider_doc_id: Field::String,
    text: Field::String,
    tag_list: Field::String,
    owner_tag: Field::String,
    download: Field::BooleanEmoji,
    printing: Field::BooleanEmoji,
    orignal: Field::BooleanEmoji,
    signature_enabled: Field::BooleanEmoji,
    from_template: Field::BelongsTo,
    approved: Field::BooleanEmoji,
    approved_by: Field::BelongsTo,
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
    approved
    orignal
    tag_list
    owner_tag
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
    orignal
    tag_list
    file
    created_at
    updated_at

    approved
    approved_by
    esign_status
    signature_enabled
    provider_doc_id
    from_template

    access_rights
    e_signatures

  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    download
    printing
    orignal
    tag_list
    rich_text_text
    provider_doc_id
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
