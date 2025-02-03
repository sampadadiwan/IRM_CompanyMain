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
    advisor_entity: Field::BelongsTo.with_options(class_name: "Entity", searchable: false),
    advisor_entity_roles: Field::String,
    id: Field::Number,
    sign_in_count: Field::Number,
    last_sign_in_at: Field::DateTime,
    first_name: Field::String,
    last_name: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    email: Field::String,
    entity_type: Field::String,
    permissions: ActiveFlagField,
    password: Field::String.with_options(searchable: false),
    password_confirmation: Field::String.with_options(searchable: false),
    phone: Field::String,
    active: Field::BooleanEmoji,
    enable_support: Field::BooleanEmoji,
    whatsapp_enabled: Field::BooleanEmoji,
    confirmed_at: Field::DateTime,
    roles: Field::HasMany,
    access_rights_cache: Field::String,
    curr_role: Field::Select.with_options(collection: ["", "employee", "investor"])
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
    sign_in_count
    last_sign_in_at
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
    whatsapp_enabled
    active
    enable_support
    last_sign_in_at
    sign_in_count
    confirmed_at
    curr_role
    entity_type
    advisor_entity
    advisor_entity_roles
    roles
    permissions
    access_rights_cache
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
    whatsapp_enabled
    active
    enable_support
    curr_role
    entity_type
    advisor_entity
    advisor_entity_roles
    roles
    permissions
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

  def permitted_attributes(action = nil)
    # This is to enable the permissions field to be editable
    super + [permissions: []] # -- Adding our now removed field to the permitted list
  end
end
