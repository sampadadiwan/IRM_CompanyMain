require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    entity: Field::BelongsTo,
    id: Field::Number,
    first_name: Field::String,
    last_name: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    email: Field::String,
    password: Field::String.with_options(searchable: false),
    password_confirmation: Field::String.with_options(searchable: false),
    phone: Field::String,
    active: Field::BooleanEmoji,
    confirmed_at: Field::DateTime,
    roles: Field::HasMany,
    curr_role: Field::String
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    first_name
    last_name
    email
    active
    created_at
    entity
    curr_role
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    entity
    id
    first_name
    last_name
    created_at
    updated_at
    email
    phone
    active
    confirmed_at
    curr_role
    roles
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    entity
    first_name
    last_name
    email
    password
    password_confirmation
    phone
    active
    curr_role
    roles
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

  # Overwrite this method to customize how users are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(user)
    user.name
  end
end
