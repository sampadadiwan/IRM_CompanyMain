class Trackable < Module
  extend ActiveSupport::Concern

  def initialize(on: %i[create update destroy], audit_fields: nil, associated_with: nil)
    super()
    @on = on
    @associated_with = associated_with
    @audit_fields = audit_fields
  end

  def included(base)
    on = @on
    associated_with = @associated_with
    base.class_eval do
      # Make all models versioned
      if @audit_fields.present?
        audited(on:, only: @audit_fields, associated_with:)
      else
        audited(on:, associated_with:)
      end
      has_associated_audits
      # Soft delete for all models
      acts_as_paranoid
    end
  end
end
