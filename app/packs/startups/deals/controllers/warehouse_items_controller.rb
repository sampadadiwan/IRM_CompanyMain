# frozen_string_literal: true

# Lists and resolves warehouse items for a deal.
#
# Warehouse items are emails the Deal Update Agent couldn't auto-file.
# This controller lets team members review pending items and either
# file them (pick the stakeholder, create the note/task) or discard them.
#
# @see WarehouseItem for the model
# @see DealIngestProcessor for the pipeline that creates warehouse items
class WarehouseItemsController < ApplicationController
  before_action :set_deal
  before_action :set_warehouse_item, only: [:resolve]
  # Pundit: authorize via @deal (not policy_scope) since warehouse items
  # are scoped to a specific deal, not listed globally.
  after_action :verify_authorized
  skip_after_action :verify_policy_scoped, only: [:index]

  # GET /deals/:deal_id/warehouse_items
  # Lists pending warehouse items for a deal.
  # Loads deal investors (for stakeholder picker) and team members
  # (for assignee dropdown when filing as task).
  def index
    authorize @deal, :show?
    @warehouse_items = @deal.warehouse_items.pending
                            .includes(agent_ingested_email: :sender_user)
                            .order(created_at: :desc)
    @deal_investors = @deal.deal_investors.includes(:investor).order("investors.investor_name")
    @team_members = deal_team_members
    @pagy, @warehouse_items = pagy(@warehouse_items)
  end

  # PATCH /deals/:deal_id/warehouse_items/:id/resolve
  # Resolves a warehouse item — files it as a note/task or discards it.
  #
  # Params:
  #   resolution        [String] "filed" or "discarded"
  #   deal_investor_id  [Integer] required when resolution is "filed"
  #   intent            [String] "meeting_note" or "task" (required when "filed")
  def resolve
    authorize @deal, :update?

    if params[:resolution] == "filed"
      file_warehouse_item!
    else
      @warehouse_item.resolve!(user: current_user, resolution: "discarded")
    end

    redirect_to resolve_redirect_path, notice: resolve_notice
  end

  private

  def set_deal
    @deal = Deal.find(params[:deal_id])
  end

  def set_warehouse_item
    @warehouse_item = @deal.warehouse_items.find(params[:id])
  end

  # File a warehouse item — create the Note or Task and resolve.
  # The created record is linked back to the email via the polymorphic
  # filed_as association on AgentIngestedEmail (match_tier "M" = manual).
  # Wrapped in a transaction to prevent partial state if any step fails.
  #
  # For tasks, accepts optional due_date and assigned_to_id params so the
  # user can override what the LLM parsed before filing.
  def file_warehouse_item!
    deal_investor = @deal.deal_investors.find(params[:deal_investor_id])
    email = @warehouse_item.agent_ingested_email
    parsed = email.parse_json || {}

    intent = case params[:intent] || @warehouse_item.parsed_intent
             when "meeting_note", "task"
               params[:intent] || @warehouse_item.parsed_intent
             else
               "meeting_note"
             end

    ActiveRecord::Base.transaction do
      item = if intent == "meeting_note"
               Note.create!(
                 entity_id: @deal.entity_id,
                 user_id: current_user.id,
                 owner: deal_investor,
                 details: parsed["body"] || "Filed from warehouse",
                 on: Date.current
               )
             else
               Task.create!(
                 entity_id: @deal.entity_id,
                 for_entity_id: @deal.entity_id,
                 user_id: current_user.id,
                 assigned_to: resolve_task_assignee,
                 owner: deal_investor,
                 details: parsed["body"] || "Filed from warehouse",
                 due_date: resolve_task_due_date(parsed)
               )
             end

      email.mark_filed!(confidence: 1.0, match_tier: "M", filed_as: item)
      @warehouse_item.resolve!(user: current_user, resolution: "filed")
    end
  end

  # Fetch users with explicit access to this deal.
  # Only includes users with a direct AccessRight on the deal —
  # company admins are excluded because they aren't necessarily
  # working on the deal and inflate the assignee dropdown.
  #
  # @return [ActiveRecord::Relation<User>]
  def deal_team_members
    access_user_ids = AccessRight.where(owner: @deal).pluck(:user_id)
    User.where(id: access_user_ids).order(:first_name, :last_name)
  end

  # Resolve the assignee for a task filed from the warehouse.
  # Uses the form-submitted assigned_to_id if present, otherwise
  # falls back to the current user.
  #
  # @return [User]
  def resolve_task_assignee
    if params[:assigned_to_id].present?
      User.find(params[:assigned_to_id])
    else
      current_user
    end
  end

  # Resolve the due date for a task filed from the warehouse.
  # Prefers the form-submitted due_date param over the LLM-parsed value.
  #
  # @param parsed [Hash] LLM parse result from the email record
  # @return [Date, nil]
  def resolve_task_due_date(parsed)
    safe_parse_date(params[:due_date].presence || parsed["due_date"])
  end

  # Parse a date string safely, returning nil for invalid or missing values.
  # LLM-stored dates in parse_json may be malformed (e.g. "TBD", "next Friday").
  #
  # @param date_string [String, nil] ISO 8601 date string from parse_json
  # @return [Date, nil]
  def safe_parse_date(date_string)
    return nil if date_string.blank?

    Date.parse(date_string)
  rescue Date::Error
    nil
  end

  # Redirect to the deal page when no more pending items remain,
  # otherwise stay on the warehouse list.
  #
  # @return [String] redirect path
  def resolve_redirect_path
    if @deal.warehouse_items.pending.exists?
      deal_warehouse_items_path(@deal)
    else
      deal_path(@deal, list_view: true)
    end
  end

  # @return [String] notice message for the redirect
  def resolve_notice
    if params[:resolution] == "filed"
      "Item filed successfully"
    else
      "Item discarded"
    end
  end
end
