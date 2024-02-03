require "administrate/base_dashboard"

class ExcerciseDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    # audits: Field::HasMany,
    entity: Field::BelongsTo,
    holding: Field::BelongsTo,
    created_holding: Field::HasOne,
    user: Field::BelongsTo,
    option_pool: Field::BelongsTo,
    id: Field::Number,
    quantity: Field::Number,
    price_cents: Field::Number,
    amount_cents: Field::Number,
    tax_cents: Field::Number,
    approved: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    tax_rate: Field::Number,
    audits: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    entity
    holding
    created_holding
    user
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    entity
    holding
    user
    option_pool
    id
    quantity
    price_cents
    amount_cents
    tax_cents
    approved
    created_at
    updated_at
    tax_rate

    created_holding
    audits

  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    quantity
    price_cents
    amount_cents
    tax_cents
    approved
    tax_rate
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

  # Overwrite this method to customize how excercises are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(excercise)
  #   "Excercise ##{excercise.id}"
  # end
end
