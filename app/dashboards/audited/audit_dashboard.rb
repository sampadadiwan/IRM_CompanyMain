require "administrate/base_dashboard"

module Audited
  class AuditDashboard < Administrate::BaseDashboard
    # ATTRIBUTE_TYPES
    # a hash that describes the type of each of the model's fields.
    #
    # Each different type represents an Administrate::Field object,
    # which determines how the attribute is displayed
    # on pages throughout the dashboard.
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      action: Field::String,
      associated: Field::Polymorphic,
      auditable: Field::Polymorphic,
      audited_changes: Field::Text,
      comment: Field::String,
      remote_address: Field::String,
      request_uuid: Field::String,
      user: Field::Polymorphic,
      username: Field::String,
      version: Field::Number,
      created_at: Field::DateTime
    }.freeze

    # COLLECTION_ATTRIBUTES
    # an array of attributes that will be displayed on the model's index page.
    #
    # By default, it's limited to four items to reduce clutter on index pages.
    # Feel free to add, remove, or rearrange items.
    COLLECTION_ATTRIBUTES = %i[
      id
      action
      associated
      auditable
      audited_changes
      user
      created_at
    ].freeze

    # SHOW_PAGE_ATTRIBUTES
    # an array of attributes that will be displayed on the model's show page.
    SHOW_PAGE_ATTRIBUTES = %i[
      id
      action
      associated
      auditable
      audited_changes
      comment
      remote_address
      request_uuid
      user
      username
      version
      created_at
    ].freeze

    # FORM_ATTRIBUTES
    # an array of attributes that will be displayed
    # on the model's form (`new` and `edit`) pages.
    FORM_ATTRIBUTES = %i[
      action
      associated
      auditable
      audited_changes
      comment
      remote_address
      request_uuid
      user
      username
      version
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

    # Overwrite this method to customize how audits are displayed
    # across all pages of the admin dashboard.
    #
    # def display_resource(audit)
    #   "Audited::Audit ##{audit.id}"
    # end
  end
end
