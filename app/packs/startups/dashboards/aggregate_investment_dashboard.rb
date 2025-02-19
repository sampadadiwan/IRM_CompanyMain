require "administrate/base_dashboard"

class AggregateInvestmentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    associated_audits: Field::HasMany,
    audits: Field::HasMany,
    deleted_at: Field::DateTime,
    entity: Field::BelongsTo,
    equity: Field::Number,
    full_diluted_percentage: Field::String.with_options(searchable: false),
    investments: Field::HasMany,
    investor: Field::BelongsTo,
    options: Field::Number,
    percentage: Field::String.with_options(searchable: false),
    preferred: Field::Number,
    preferred_converted_qty: Field::Number,
    shareholder: Field::String,
    units: Field::Number,
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
    associated_audits
    audits
    deleted_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    associated_audits
    audits
    deleted_at
    entity
    equity
    full_diluted_percentage
    investments
    investor
    options
    percentage
    preferred
    preferred_converted_qty
    shareholder
    units
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    associated_audits
    audits
    deleted_at
    entity
    equity
    full_diluted_percentage
    investments
    investor
    options
    percentage
    preferred
    preferred_converted_qty
    shareholder
    units
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

  # Overwrite this method to customize how aggregate investments are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(aggregate_investment)
  #   "AggregateInvestment ##{aggregate_investment.id}"
  # end
end
