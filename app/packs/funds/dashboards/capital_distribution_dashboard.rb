require "administrate/base_dashboard"

class CapitalDistributionDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    fund: Field::BelongsTo,
    entity: Field::BelongsTo,
    form_type: Field::BelongsTo,
    capital_distribution_payments: Field::HasMany,
    id: Field::Number,
    gross_amount_cents: Field::String.with_options(searchable: false),
    carry_cents: Field::String.with_options(searchable: false),
    distribution_date: Field::Date,
    properties: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    title: Field::String,
    completed: Field::Boolean,
    distribution_amount_cents: Field::String.with_options(searchable: false),
    net_amount_cents: Field::String.with_options(searchable: false)
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    fund
    entity
    title
    gross_amount_cents
    carry_cents
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    fund
    entity
    form_type
    capital_distribution_payments
    id
    gross_amount_cents
    carry_cents
    distribution_date
    properties
    created_at
    updated_at
    title
    completed
    distribution_amount_cents
    net_amount_cents
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    fund
    entity
    form_type
    capital_distribution_payments
    gross_amount_cents
    carry_cents
    distribution_date
    properties
    title
    completed
    distribution_amount_cents
    net_amount_cents
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

  # Overwrite this method to customize how capital distributions are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(capital_distribution)
    "CapitalDistribution #{capital_distribution.title}"
  end
end
