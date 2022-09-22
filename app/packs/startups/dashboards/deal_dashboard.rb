require "administrate/base_dashboard"

class DealDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    entity: Field::BelongsTo,
    deal_investors: Field::HasMany,
    investors: Field::HasMany,
    deal_activities: Field::HasMany,
    access_rights: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    amount: ObfuscatedField,
    status: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    start_date: Field::Date,
    end_date: Field::Date
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    name
    amount
    entity
    status
    start_date
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    entity
    name
    amount
    status
    created_at
    updated_at
    start_date
    end_date
    deal_investors
    deal_activities
    access_rights
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    status
    start_date
    end_date
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

  # Overwrite this method to customize how deals are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(deal)
    deal.name
  end
end
