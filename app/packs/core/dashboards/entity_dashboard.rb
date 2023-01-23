require "administrate/base_dashboard"

class EntityDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    documents: Field::HasMany,
    employees: Field::HasMany,
    entity_setting: Field::HasOne,
    investments: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    sub_domain: Field::String,
    url: Field::String,
    category: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    active: Field::BooleanEmoji,
    activity_docs_required_for_completion: Field::BooleanEmoji,
    activity_details_required_for_na: Field::BooleanEmoji,
    entity_type: Field::Select.with_options(collection: Entity::TYPES),
    currency: Field::Select.with_options(collection: ENV["CURRENCY"].split(",")),
    created_by: Field::Number,
    investor_categories: Field::String,
    instrument_types: Field::String,
    enable_documents: Field::BooleanEmoji,
    enable_deals: Field::BooleanEmoji,
    enable_investments: Field::BooleanEmoji,
    enable_holdings: Field::BooleanEmoji,
    enable_secondary_sale: Field::BooleanEmoji,
    enable_funds: Field::BooleanEmoji,
    enable_options: Field::BooleanEmoji,
    enable_captable: Field::BooleanEmoji,
    enable_investor_kyc: Field::BooleanEmoji,
    enable_inv_opportunities: Field::BooleanEmoji
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    name
    url
    entity_type
    category
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    sub_domain
    url
    category
    created_at
    updated_at
    active
    currency
    entity_type
    created_by
    investor_categories
    instrument_types
    enable_documents
    enable_deals
    enable_investments
    enable_holdings
    enable_secondary_sale
    enable_funds
    enable_inv_opportunities
    enable_options
    enable_captable
    enable_investor_kyc
    employees
    entity_setting
    activity_docs_required_for_completion
    activity_details_required_for_na
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    sub_domain
    url
    currency
    category
    active
    entity_type
    investor_categories
    instrument_types
    enable_documents
    enable_deals
    enable_investments
    enable_holdings
    enable_secondary_sale
    enable_funds
    enable_inv_opportunities
    enable_options
    enable_captable
    enable_investor_kyc
    activity_docs_required_for_completion
    activity_details_required_for_na
    entity_setting
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

  # Overwrite this method to customize how entities are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(entity)
    entity.name
  end
end
