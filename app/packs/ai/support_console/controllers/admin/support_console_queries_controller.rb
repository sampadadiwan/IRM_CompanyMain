# frozen_string_literal: true

module Admin
  # Review list of Support Console lookups, for super users (design card ⑧).
  class SupportConsoleQueriesController < Admin::ApplicationController
    # Read-only: the record is an audit trail.
    def edit = head(:not_found)
    def update = head(:not_found)
    def new = head(:not_found)
    def create = head(:not_found)
    def destroy = head(:not_found)

    # ?flagged=true (the alert's link), ?user_id=, ?entity_id= narrow the list.
    def apply_resource_filters(resources)
      resources = resources.where(flagged: true) if params[:flagged] == "true"
      resources = resources.where(user_id: params[:user_id]) if params[:user_id].present?
      resources = resources.where(entity_id: params[:entity_id]) if params[:entity_id].present?
      resources
    end

    # Newest first unless the user sorts.
    def default_sorting_attribute
      :created_at
    end

    def default_sorting_direction
      :desc
    end
  end
end
