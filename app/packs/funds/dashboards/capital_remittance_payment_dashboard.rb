require "administrate/base_dashboard"

class CapitalRemittancePaymentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    amount_cents: Field::String.with_options(searchable: false),
    capital_remittance: Field::BelongsTo,
    entity: Field::BelongsTo,
    exchange_rate: Field::BelongsTo,
    folio_amount_cents: Field::String.with_options(searchable: false),
    fund: Field::BelongsTo,
    notes: Field::Text,
    payment_date: Field::Date,
    payment_proof_data: Field::Text,
    properties: Field::Text,
    reference_no: Field::String,
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
    amount_cents
    capital_remittance
    entity
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    amount_cents
    capital_remittance
    entity
    exchange_rate
    folio_amount_cents
    fund
    notes
    payment_date
    payment_proof_data
    properties
    reference_no
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    amount_cents
    capital_remittance
    entity
    exchange_rate
    folio_amount_cents
    fund
    notes
    payment_date
    reference_no
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

  # Overwrite this method to customize how capital remittance payments are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(capital_remittance_payment)
  #   "CapitalRemittancePayment ##{capital_remittance_payment.id}"
  # end
end
