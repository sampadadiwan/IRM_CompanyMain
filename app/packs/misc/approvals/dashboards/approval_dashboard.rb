require "administrate/base_dashboard"

class ApprovalDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    approval_responses: Field::HasMany,
    approved: Field::Boolean,
    documents: Field::HasMany,
    due_date: Field::Date,
    entity: Field::BelongsTo,
    locked: Field::BooleanEmoji,
    pending_count: Field::Number,
    pending_investors: Field::HasMany,
    properties: Field::Text,
    rejected_count: Field::Number,
    response_status: Field::String,
    rich_text_agreements_reference: Field::HasOne,
    title: Field::String,
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
    title
    response_status
    due_date
    locked
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    approved
    due_date
    locked
    response_status
    created_at
    updated_at
    approval_responses
    documents
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    approved
    due_date
    entity
    locked
    title
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how approvals are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(approval)
    approval.title
  end
end
