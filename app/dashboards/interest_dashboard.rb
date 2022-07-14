require "administrate/base_dashboard"

class InterestDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    user: Field::BelongsTo,
    secondary_sale: Field::BelongsTo,
    interest_entity: Field::BelongsTo,
    entity: Field::BelongsTo,
    id: Field::Number,
    quantity: Field::Number,
    price: Field::String.with_options(searchable: false),
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    short_listed: Field::BooleanEmoji,
    escrow_deposited: Field::BooleanEmoji,
    interest_id: Field::Number
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    user
    secondary_sale
    interest_entity
    entity
    price
    quantity
    short_listed
    escrow_deposited
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    user
    secondary_sale
    interest_entity
    entity
    quantity
    price
    short_listed
    escrow_deposited
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    quantity
    price
    short_listed
    escrow_deposited
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

  # Overwrite this method to customize how interests are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(interest)
  #   "Interest ##{interest.id}"
  # end
end
