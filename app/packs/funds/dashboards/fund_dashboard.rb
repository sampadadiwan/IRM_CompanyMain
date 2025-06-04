require "administrate/base_dashboard"

class FundDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    entity: Field::BelongsTo,
    portfolio_cost_type: Field::Select.with_options(collection: Fund::PORTFOLIO_COST_TYPES),
    documents: Field::HasMany,
    valuations: Field::HasMany,
    capital_remittances: Field::HasMany,
    capital_commitments: Field::HasMany,
    capital_distributions: Field::HasMany,
    capital_calls: Field::HasMany,
    access_rights: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    committed_amount_cents: Field::String.with_options(searchable: false),
    details: Field::Text,
    collected_amount_cents: Field::String.with_options(searchable: false),
    tag_list: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    call_amount_cents: Field::String.with_options(searchable: false),
    properties: Field::Text,
    distribution_amount_cents: Field::String.with_options(searchable: false),
    audits: Field::HasMany,
    editable_formulas: Field::BooleanEmoji
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    entity
    name
    editable_formulas
    tag_list
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    entity
    id
    name
    editable_formulas
    portfolio_cost_type
    committed_amount_cents
    details
    collected_amount_cents
    tag_list
    created_at
    updated_at
    call_amount_cents
    properties
    distribution_amount_cents
    documents
    valuations
    capital_remittances
    capital_commitments
    capital_distributions
    capital_calls
    access_rights
    audits

  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[

    name
    portfolio_cost_type
    editable_formulas
    committed_amount_cents
    details
    collected_amount_cents
    tag_list
    call_amount_cents
    distribution_amount_cents
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

  # Overwrite this method to customize how funds are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(fund)
    fund.name
  end
end
