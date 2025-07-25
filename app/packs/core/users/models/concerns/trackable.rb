class Trackable < Module
  extend ActiveSupport::Concern

  def initialize(on: %i[create update destroy], audit_fields: nil, associated_with: nil)
    @on = on
    @associated_with = associated_with
    @audit_fields = audit_fields
    super()
  end

  def included(base)
    on = @on
    associated_with = @associated_with
    audit_fields    = @audit_fields

    base.class_eval do
      # Soft delete for all models
      acts_as_paranoid

      # Make all models versioned
      if audit_fields.present?
        audited only: audit_fields, on:, associated_with:
      else
        audited(on:, associated_with:)
      end

      # Audit trails
      has_associated_audits
    end
  end
end
