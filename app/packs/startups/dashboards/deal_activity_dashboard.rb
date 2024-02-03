require "administrate/base_dashboard"

class DealActivityDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    deal: Field::BelongsTo,
    deal_investor: Field::BelongsTo,
    entity: Field::BelongsTo,
    id: Field::Number,
    by_date: Field::Date,
    status: Field::String,
    completed: Field::BooleanEmoji,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    title: Field::String,
    details: Field::Text,
    sequence: Field::Number,
    days: Field::Number,
    audits: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    title
    status
    completed
    deal
    deal_investor
    entity
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    title
    id
    by_date
    status
    completed
    created_at
    updated_at
    sequence
    days
    deal
    deal_investor
    entity
    audits

  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    status
    completed
    days
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

  # Overwrite this method to customize how deal activities are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(deal_activity)
  #   "DealActivity ##{deal_activity.id}"
  # end
end
