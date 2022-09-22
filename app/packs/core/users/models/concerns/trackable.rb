module Trackable
  extend ActiveSupport::Concern

  included do
    # Make all models versioned
    has_paper_trail

    # Soft delete for all models
    acts_as_paranoid
  end
end
