module Admin
  class ValidationRulesController < Admin::ApplicationController
    # When ?entity_id=X is in the URL, show only rules that apply to that entity:
    # its global defaults (entity_id nil) plus any entity-specific custom rules.
    # Without the param, show everything (super/support full view).
    def scoped_resource
      base = ValidationRule.all
      if params[:entity_id].present?
        base.where(entity_id: [nil, params[:entity_id]])
      else
        base
      end
    end

    # Override apply_resource_filters so the entity_id param survives pagination/sorting
    def apply_resource_filters(resources)
      resources
    end
  end
end
