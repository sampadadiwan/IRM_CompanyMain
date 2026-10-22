class Trackable < Module
  extend ActiveSupport::Concern

  # audit_fields — audit only these columns (audited `only:`)
  # audit_except — audit every column but these, e.g. values a recompute overwrites (audited `except:`)
  # audit_if     — audit only while this method returns true, e.g. a flag the edit screen sets (audited `if:`)
  def initialize(on: %i[create update destroy], audit_fields: nil, audit_except: nil, audit_if: nil, associated_with: nil)
    @on = on
    @associated_with = associated_with
    @audit_fields = audit_fields
    @audit_except = audit_except
    @audit_if = audit_if
    super()
  end

  def included(base)
    # Only the options a model asked for, so a plain Trackable.new audits exactly as before
    options = { on: @on, associated_with: @associated_with }
    options[:only] = @audit_fields if @audit_fields.present?
    options[:except] = @audit_except if @audit_fields.blank? && @audit_except.present?
    options[:if] = @audit_if if @audit_if

    base.class_eval do
      # Soft delete for all models
      acts_as_paranoid

      # Make all models versioned
      audited(**options)

      # Audit trails
      has_associated_audits
    end
  end
end
