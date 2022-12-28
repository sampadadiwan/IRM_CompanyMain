require "administrate/base_dashboard"

class OptionPoolDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    # audits: Field::HasMany,
    entity: Field::BelongsTo,
    funding_round: Field::BelongsTo,
    holdings: Field::HasMany,
    excercises: Field::HasMany,
    vesting_schedules: Field::HasMany,
    certificate_signature_attachment: Field::HasOne,
    id: Field::Number,
    name: Field::String,
    start_date: Field::Date,
    number_of_options: Field::Number,
    excercise_price_cents: Field::Number,
    excercise_period_months: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    allocated_quantity: Field::Number,
    excercised_quantity: Field::Number,
    vested_quantity: Field::Number,
    lapsed_quantity: Field::Number,
    approved: Field::Boolean,
    versions: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    entity
    funding_round
    name
    number_of_options
    allocated_quantity
    excercised_quantity
    vested_quantity
    approved
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    start_date
    number_of_options
    excercise_price_cents
    excercise_period_months
    created_at
    updated_at
    allocated_quantity
    excercised_quantity
    vested_quantity
    lapsed_quantity
    approved
    holdings
    excercises
    versions
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    start_date
    number_of_options
    excercise_price_cents
    excercise_period_months
    allocated_quantity
    excercised_quantity
    vested_quantity
    lapsed_quantity
    approved
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

  # Overwrite this method to customize how option pools are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(option_pool)
  #   "OptionPool ##{option_pool.id}"
  # end
end
