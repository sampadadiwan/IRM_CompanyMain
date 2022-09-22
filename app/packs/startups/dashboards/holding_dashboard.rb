require "administrate/base_dashboard"

class HoldingDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    # audits: Field::HasMany,
    excercises: Field::HasMany,
    user: Field::BelongsTo,
    entity: Field::BelongsTo,
    id: Field::Number,
    quantity: ObfuscatedField,
    value: ObfuscatedField,
    price: ObfuscatedField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    approved: Field::BooleanEmoji,
    cancelled: Field::BooleanEmoji,
    lapsed: Field::BooleanEmoji,
    emp_ack: Field::BooleanEmoji,
    investment_instrument: Field::Select.with_options(collection: Investment::INSTRUMENT_TYPES)
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    user
    entity
    quantity
    investment_instrument
    approved
    cancelled
    lapsed
    emp_ack
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    user
    entity
    investment_instrument
    quantity
    price
    value
    created_at
    updated_at
    approved
    cancelled
    lapsed
    emp_ack
    excercises
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[

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

  # Overwrite this method to customize how holdings are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(holding)
  #   "Holding ##{holding.id}"
  # end
end
