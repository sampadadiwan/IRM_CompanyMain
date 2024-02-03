module Trackable
  extend ActiveSupport::Concern

  included do
    # Make all models versioned
    audited on: %i[create update destroy]
    has_associated_audits
    # Soft delete for all models
    acts_as_paranoid
  end
end
