require "administrate/base_dashboard"

class OfferDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    user: Field::BelongsTo,
    entity: Field::BelongsTo,
    secondary_sale: Field::BelongsTo,
    granter: Field::BelongsTo,
    documents: Field::HasMany,

    id: Field::Number,
    quantity: Field::Number,
    percentage: Field::String.with_options(searchable: false),
    notes: Field::Text,

    full_name: Field::String,
    PAN: Field::String,
    address: Field::String,
    bank_account_number: Field::String,
    ifsc_code: Field::String,
    demat: Field::String,
    city: Field::String,

    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    approved: Field::BooleanEmoji,
    verified: Field::BooleanEmoji,
    pan_verified: Field::BooleanEmoji,
    pan_verification_status: Field::String,
    bank_verified: Field::BooleanEmoji,
    bank_verification_status: Field::String,
    comments: Field::Text,
    auto_match: Field::BooleanEmoji,
    granted_by_user_id: Field::Number,
    final_agreement: Field::BooleanEmoji,
    audits: Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    user
    entity
    secondary_sale
    quantity
    approved
    verified
    final_agreement
    auto_match
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    user
    entity
    secondary_sale
    granter
    id
    quantity
    percentage

    full_name
    PAN
    pan_verified
    pan_verification_status
    address
    bank_account_number
    bank_verification_status
    ifsc_code
    bank_verified
    demat
    city

    notes
    created_at
    updated_at
    approved
    verified
    final_agreement

    auto_match
    granted_by_user_id

    documents
    audits
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    user
    entity
    secondary_sale
    granter
    quantity
    percentage

    full_name
    PAN
    pan_verified
    pan_verification_status
    address
    bank_account_number
    bank_verification_status
    ifsc_code
    bank_verified
    demat
    city
    notes
    final_agreement
    auto_match
    granted_by_user_id
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

  # Overwrite this method to customize how offers are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(offer)
  #   "Offer ##{offer.id}"
  # end
end
