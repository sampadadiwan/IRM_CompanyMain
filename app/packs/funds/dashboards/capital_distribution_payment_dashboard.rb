require "administrate/base_dashboard"

class CapitalDistributionPaymentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    fund: Field::BelongsTo,
    entity: Field::BelongsTo,
    capital_distribution: Field::BelongsTo,
    investor: Field::BelongsTo,
    id: Field::Number,
    amount_cents: Field::String.with_options(searchable: false),
    payment_date: Field::Date,
    properties: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    completed: Field::Boolean,
    audits: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    fund
    entity
    capital_distribution
    investor
    payment_date
    amount_cents
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    fund
    entity
    capital_distribution
    investor
    id
    amount_cents
    payment_date
    properties
    created_at
    updated_at
    completed
    audits
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    fund
    entity
    capital_distribution
    investor
    amount_cents
    payment_date
    completed
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

  # Overwrite this method to customize how capital distribution payments are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(capital_distribution_payment)
  #   "CapitalDistributionPayment ##{capital_distribution_payment.id}"
  # end
end
