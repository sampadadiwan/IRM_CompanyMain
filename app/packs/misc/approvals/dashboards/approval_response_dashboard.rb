require "administrate/base_dashboard"

class ApprovalResponseDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    approval: Field::BelongsTo,
    entity: Field::BelongsTo,
    investor: Field::BelongsTo,
    notification_sent: Field::Boolean,
    response_entity: Field::BelongsTo,
    response_user: Field::BelongsTo,
    rich_text_details: Field::HasOne,
    status: Field::String,
    versions: Field::HasMany,
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
    approval
    entity
    investor
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    approval
    entity
    investor
    notification_sent
    response_entity
    response_user
    rich_text_details
    status
    versions
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    approval
    entity
    investor
    notification_sent
    response_entity
    response_user
    rich_text_details
    status
    versions
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

  # Overwrite this method to customize how approval responses are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(approval_response)
  #   "ApprovalResponse ##{approval_response.id}"
  # end
end
