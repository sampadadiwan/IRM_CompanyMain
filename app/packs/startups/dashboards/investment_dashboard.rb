require "administrate/base_dashboard"

class InvestmentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    # audits: Field::HasMany,
    investor: Field::BelongsTo,
    entity: Field::BelongsTo,
    id: Field::Number,
    investment_type: Field::String,
    investor_type: Field::String,
    status: Field::String,
    investment_instrument: Field::String,
    quantity: ObfuscatedField,
    amount_cents: ObfuscatedField,
    price_cents: ObfuscatedField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    category: Field::String,
    audits: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    investment_type
    investor
    entity
    investment_instrument
    quantity
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    category
    investor
    entity
    investment_type
    status
    investment_instrument
    quantity
    created_at
    updated_at
    audits
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    status
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

  # Overwrite this method to customize how investments are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(investment)
  #   "Investment ##{investment.id}"
  # end
end
