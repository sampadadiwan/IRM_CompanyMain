require "administrate/base_dashboard"

class SecondarySaleDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    entity: Field::BelongsTo.with_options(
      searchable: true,
      searchable_fields: ['name']
    ),
    access_rights: Field::HasMany,
    public_docs_attachments: Field::HasMany,
    public_docs_blobs: Field::HasMany,
    offers: Field::HasMany,
    interests: Field::HasMany,
    id: Field::Number,
    name: Field::String,
    custom_matching_fields: Field::String,
    seller_doc_list: Field::String,
    buyer_doc_list: Field::String,
    support_email: Field::String,
    show_quantity: Field::String,
    start_date: Field::Date,
    end_date: Field::Date,
    percent_allowed: ObfuscatedField,
    min_price: ObfuscatedField,
    max_price: ObfuscatedField,
    active: Field::BooleanEmoji,
    no_offer_emails: Field::BooleanEmoji,
    no_interest_emails: Field::BooleanEmoji,
    manage_offers: Field::BooleanEmoji,
    manage_interests: Field::BooleanEmoji,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    total_offered_quantity: Field::Number,
    total_interest_quantity: Field::Number,
    visible_externally: Field::BooleanEmoji,
    seller_transaction_fees_pct: Field::Number,
    disable_pan_kyc: Field::BooleanEmoji,
    disable_bank_kyc: Field::BooleanEmoji,
    secondary_sale_form_type_id: Field::Number,
    offer_form_type_id: Field::Number,
    interest_form_type_id: Field::Number,
    sale_type: Field::Select.with_options(collection: SecondarySale::SALE_TYPES),
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
    entity
    start_date
    end_date
    min_price
    max_price
    percent_allowed
    total_offered_quantity
    visible_externally
    sale_type
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    sale_type
    start_date
    end_date
    percent_allowed
    min_price
    max_price
    custom_matching_fields
    active
    seller_doc_list
    buyer_doc_list
    support_email
    show_quantity
    no_offer_emails
    manage_offers
    no_interest_emails
    manage_interests
    created_at
    updated_at
    total_offered_quantity
    total_interest_quantity
    visible_externally
    disable_pan_kyc
    disable_bank_kyc
    secondary_sale_form_type_id
    offer_form_type_id
    interest_form_type_id
    entity
    access_rights
    offers
    interests
    audits

  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    sale_type
    start_date
    end_date
    custom_matching_fields
    support_email
    show_quantity

    visible_externally
    disable_pan_kyc
    disable_bank_kyc

    no_offer_emails
    manage_offers
    no_interest_emails
    manage_interests

    secondary_sale_form_type_id
    offer_form_type_id
    interest_form_type_id
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

  # Overwrite this method to customize how secondary sales are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(secondary_sale)
    secondary_sale.name
  end
end
