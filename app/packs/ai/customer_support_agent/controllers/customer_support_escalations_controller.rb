# frozen_string_literal: true

# Displays escalation details with full conversation history and allows
# support team members to resolve or dismiss escalated sessions.
# Scoped to the current user's mapped entities via SupportClientMapping.
#
# @see CustomerSupportEscalation
# @see CustomerSupportEscalationPolicy
class CustomerSupportEscalationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_escalation

  # GET /customer_support_escalations/:id
  #
  # @param id [Integer] the CustomerSupportEscalation ID
  def show
    @session = @escalation.agent_chat_session
    @messages = @session.agent_chat_messages
                        .where(created_at: ..(@escalation.created_at + 1.second))
                        .order(:created_at).last(2)
    @entity = @escalation.entity
    @user = @escalation.user
  end

  # PATCH /customer_support_escalations/:id
  #
  # @param id [Integer] the CustomerSupportEscalation ID
  # @param status [String] new status: "resolved" or "dismissed"
  def update
    if params[:status] == "resolved"
      @escalation.resolve!(current_user)
    else
      @escalation.update!(status: params[:status])
    end

    redirect_to customer_support_escalation_path(@escalation), notice: "Escalation marked as #{params[:status]}."
  end

  private

  # Finds the escalation scoped to the current user's mapped entities.
  # Raises ActiveRecord::RecordNotFound if the user is not mapped to the escalation's entity.
  #
  # @return [CustomerSupportEscalation]
  def set_escalation
    @escalation = policy_scope(CustomerSupportEscalation).find(params[:id])
    authorize @escalation
  end
end
