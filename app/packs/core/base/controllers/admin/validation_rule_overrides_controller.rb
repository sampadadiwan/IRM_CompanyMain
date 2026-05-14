module Admin
  class ValidationRuleOverridesController < Admin::ApplicationController
    # Only show overrides belonging to this admin's entity
    def scoped_resource
      ValidationRuleOverride.where(entity_id: current_user.entity_id)
    end
  end
end
