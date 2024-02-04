class Trackable < Module
  extend ActiveSupport::Concern

  def initialize(on: %i[create update destroy], associated_with: nil)
    super()
    @on = on
    @associated_with = associated_with
  end

  def included(base)
    on = @on
    associated_with = @associated_with
    base.class_eval do
      # Make all models versioned
      audited(on:, associated_with:)
      has_associated_audits
      # Soft delete for all models
      acts_as_paranoid
    end
  end
end
