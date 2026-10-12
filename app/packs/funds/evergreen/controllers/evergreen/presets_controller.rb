# A typical setup's values as JSON, so the evergreen wizard can fill its fields in place — on New Fund
# (no fund yet) and on Evergreen Settings — without reloading the page or losing what was typed.
# Worked examples H1 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples
module Evergreen
  class PresetsController < ApplicationController
    def show
      # Same rule as New Fund: the user may create funds, on an entity with evergreen funds switched on
      authorize Fund.new(entity_id: current_user.entity_id), :new?
      return head :not_found unless current_user.entity.permissions.enable_evergreen_funds?

      values = EvergreenPresets.values(params[:name])
      return head :not_found unless values

      render json: values
    end
  end
end
