# frozen_string_literal: true

# Dashboard for Caphive support team to review flagged agent responses,
# negative user feedback, and escalations across all entities.
# Single CS queue — feedback items and escalations appear in one place.
#
# @see CsFeedbackReviewPolicy
# @see AgentChatMessageFeedback
# @see CustomerSupportEscalation
class CsFeedbackReviewsController < ApplicationController
  before_action :set_feedback, only: %i[show update retest]

  # GET /cs_feedback_reviews
  #
  # @param status [String] filter by feedback status (open/needs_review/resolved/dismissed/pending_engineering)
  # @param rating [String] filter by user rating (positive/negative)
  # @param entity_id [Integer] filter by entity
  # @param judge_max [Integer] filter feedbacks where judge_total <= this threshold
  # @param tab [String] "feedbacks" (default) or "escalations"
  def index
    authorize :cs_feedback_review

    @tab = params[:tab].presence || "feedbacks"
    # Scope to entities this support user is mapped to
    @mapped_entity_ids = SupportClientMapping.where(user: current_user, enabled: true).pluck(:entity_id)

    # Feedback queue
    feedbacks = policy_scope(AgentChatMessageFeedback)
                .includes(agent_chat_message: { agent_chat_session: %i[support_agent analyst] })
    feedbacks = feedbacks.where(status: params[:status]) if params[:status].present?
    feedbacks = feedbacks.where(rating: params[:rating]) if params[:rating].present?
    feedbacks = feedbacks.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    feedbacks = feedbacks.where(judge_total: ..params[:judge_max].to_i) if params[:judge_max].present?
    feedbacks = feedbacks.order(created_at: :desc)
    @pagy_feedbacks, @feedbacks = pagy(feedbacks, page_param: :feedbacks_page, items: 20)

    # Preload user questions for the current page of feedbacks (avoids N+1 in the partial)
    if @feedbacks.any?
      session_ids = @feedbacks.map { |f| f.agent_chat_message.agent_chat_session_id }.uniq
      all_messages = AgentChatMessage.where(agent_chat_session_id: session_ids)
                                     .order(created_at: :desc)
      @user_questions_by_message_id = {}
      @feedbacks.each do |f|
        msg = f.agent_chat_message
        question = all_messages.find do |m|
          m.agent_chat_session_id == msg.agent_chat_session_id &&
            m.role == "user" &&
            m.created_at < msg.created_at
        end
        @user_questions_by_message_id[msg.id] = question
      end
    else
      @user_questions_by_message_id = {}
    end

    # Escalation queue
    escalations = CustomerSupportEscalation.where(entity_id: @mapped_entity_ids)
                                           .includes(agent_chat_session: %i[support_agent analyst])

    escalations = escalations.where(status: params[:escalation_status]) if params[:escalation_status].present?
    escalations = escalations.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    escalations = escalations.order(created_at: :desc)
    @pagy_escalations, @escalations = pagy(escalations, page_param: :escalations_page, items: 20)

    # Preload linked feedbacks for escalations (avoids N+1 in the partial)
    if @escalations.any?
      esc_session_ids = @escalations.map(&:agent_chat_session_id).uniq
      latest_feedbacks = AgentChatMessageFeedback
                         .joins(:agent_chat_message)
                         .where(agent_chat_messages: { agent_chat_session_id: esc_session_ids, role: "assistant" })
                         .order(created_at: :desc)
      @feedback_by_session_id = {}
      esc_session_ids.each do |sid|
        @feedback_by_session_id[sid] = latest_feedbacks.find { |f| f.agent_chat_message.agent_chat_session_id == sid }
      end
    else
      @feedback_by_session_id = {}
    end
  end

  # GET /cs_feedback_reviews/:id
  def show
    authorize @feedback

    @message = @feedback.agent_chat_message
    @session = @message.agent_chat_session

    # The user question is the most recent 'user' message before this assistant message
    @user_question = @session.agent_chat_messages
                             .where(role: "user")
                             .where("created_at < ?", @message.created_at)
                             .order(created_at: :desc)
                             .first

    # Linked escalation (if this session was escalated)
    @escalation = CustomerSupportEscalation.find_by(
      agent_chat_session_id: @session.id,
      status: "open"
    )
  end

  # PATCH /cs_feedback_reviews/:id
  #
  # @param status [String] new status: resolved/dismissed/pending_engineering
  # @param resolution_notes [String] required note explaining the action
  def update
    authorize @feedback

    @feedback.assign_attributes(
      status: params[:status],
      resolution_notes: params[:resolution_notes],
      reviewed_by: current_user
    )

    if @feedback.save
      # If resolving and there's a linked open escalation, resolve it too
      if params[:status] == "resolved"
        linked_escalation = CustomerSupportEscalation.find_by(
          agent_chat_session_id: @feedback.agent_chat_message.agent_chat_session_id,
          status: "open"
        )
        linked_escalation&.resolve!(current_user, notes: params[:resolution_notes])
      end

      redirect_to cs_feedback_review_path(@feedback), notice: "Feedback marked as #{params[:status]}."
    else
      set_show_dependencies
      flash.now[:alert] = @feedback.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  # POST /cs_feedback_reviews/:id/retest
  #
  # Replays the original user question through GenericChatAgent in a new session.
  # Stores the new response so the show view can render a side-by-side comparison.
  def retest
    authorize @feedback, :retest?

    @message = @feedback.agent_chat_message
    @session = @message.agent_chat_session
    support_agent = @session.support_agent

    # Find the original user question
    user_question = @session.agent_chat_messages
                            .where(role: "user")
                            .where("created_at < ?", @message.created_at)
                            .order(created_at: :desc)
                            .first

    if user_question.nil?
      redirect_to cs_feedback_review_path(@feedback), alert: "Could not find the original user question."
      return
    end

    # Run through GenericChatAgent with a fresh session (new analyst_id = current support user)
    result = GenericChatAgent.call(
      support_agent_id: support_agent.id,
      target: support_agent,
      user_message: user_question.content,
      analyst_id: current_user.id
    )

    if result.success?
      @retest_response = result[:ai_response]
      @retest_session_id = result[:chat_session]&.id
    else
      @retest_error = "Re-test failed. The agent could not generate a response."
    end

    set_show_dependencies
    render :show
  end

  private

  # @return [AgentChatMessageFeedback]
  def set_feedback
    @feedback = AgentChatMessageFeedback.find(params[:id])
  end

  # Loads dependencies needed by the show template (used by both show and retest)
  def set_show_dependencies
    @message = @feedback.agent_chat_message
    @session = @message.agent_chat_session
    @user_question = @session.agent_chat_messages
                             .where(role: "user")
                             .where("created_at < ?", @message.created_at)
                             .order(created_at: :desc)
                             .first
    @escalation = CustomerSupportEscalation.find_by(
      agent_chat_session_id: @session.id,
      status: "open"
    )
  end
end
