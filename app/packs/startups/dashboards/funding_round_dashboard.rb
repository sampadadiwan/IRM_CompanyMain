require "administrate/base_dashboard"

class FundingRoundDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    # audits: Field::HasMany,
    entity: Field::BelongsTo.with_options(
      searchable: true,
      searchable_fields: ['name']
    ),
    investments: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    currency: Field::String,
    pre_money_valuation_cents: ObfuscatedField,
    post_money_valuation_cents: ObfuscatedField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    amount_raised_cents: ObfuscatedField,
    status: Field::String,
    closed_on: Field::Date,
    deleted_at: Field::DateTime,
    audits: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    name
    amount_raised_cents
    currency
    entity
    created_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    entity
    investments
    id
    name
    currency
    pre_money_valuation_cents
    post_money_valuation_cents
    created_at
    updated_at
    amount_raised_cents
    status
    closed_on
    deleted_at
    investments
    audits
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    status
    closed_on
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

  # Overwrite this method to customize how funding rounds are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(funding_round)
    funding_round.name
  end
end
