require "administrate/base_dashboard"

class EntityDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    parent_entity: Field::BelongsTo.with_options(class_name: "Entity"),
    documents: Field::HasMany,
    employees: Field::HasMany,
    investors: Field::HasMany,
    investees: Field::HasMany,
    entity_setting: Field::HasOne,
    investments: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    pan: Field::String,
    primary_email: Field::String,
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
    tracking_currency: Field::Select.with_options(collection: ENV["CURRENCY"].split(",")),
    created_by: Field::Number,
    investor_categories: Field::String,
    instrument_types: Field::String,
    permissions: ActiveFlagField,
    customization_flags: ActiveFlagField,
    support_agents: ActiveFlagField
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    name
    primary_email
    entity_type
    permissions
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    pan
    primary_email
    parent_entity
    sub_domain
    url
    category
    permissions
    support_agents
    customization_flags
    created_at
    updated_at
    active
    currency
    tracking_currency
    entity_type
    created_by
    investor_categories
    instrument_types
    employees
    investors
    investees
    entity_setting
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    pan
    primary_email
    parent_entity
    sub_domain
    url
    currency
    tracking_currency
    category
    active
    entity_type
    investor_categories
    instrument_types
    activity_docs_required_for_completion
    activity_details_required_for_na
    permissions
    support_agents
    customization_flags
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

  def permitted_attributes(action = nil)
    # This is to enable the custom_flags field to be editable
    super + [permissions: [], customization_flags: []] # -- Adding our now removed field to the permitted list
  end
end
