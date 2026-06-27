# frozen_string_literal: true

# Orchestrates inbound WhatsApp conversations.
#
# Responsibilities:
#   1. Identify the user and entity from the incoming message.
#   2. Find or create a WhatsApp-channel AgentChatSession.
#   3. Drive a state machine through:
#        nil / awaiting_agent_selection → handle_agent_selection
#        awaiting_fund_selection        → handle_fund_selection
#        active                         → handle_message (or feedback)
#   4. Call GenericChatAgent for active sessions and return the response via WATI.
#
# The dispatcher only owns channel-specific concerns (menus, fund selection,
# feedback prompts, response formatting). The agent layer remains channel-agnostic.
#
# @see WhatsappAgentJob
# @see GenericChatAgent
# @see WhatsappResponseFormatter
class WhatsappChatDispatcher
  SESSION_TIMEOUT = 30.minutes

  MENU_KEYWORD_REGEX = /\A\s*(menu)\s*\z/i
  GOODBYE_KEYWORD_REGEX = /\b(thanks|bye|done)\b/i

  # @param user_id [Integer]
  # @param message_text [String]
  # @param conversation_id [String] WATI conversation ID from the inbound webhook
  def self.call(user_id:, message_text:, conversation_id: nil)
    new(user_id: user_id, message_text: message_text, conversation_id: conversation_id).call
  end

  def initialize(user_id:, message_text:, conversation_id: nil)
    @user_id = user_id
    @user            = User.find_by(id: user_id)
    @message         = message_text.to_s.strip
    @conversation_id = conversation_id.presence
  end

  def call
    unless @user
      send_unrecognised_user_message
      return
    end

    session = find_or_create_wa_session

    unless session
      # message is already sent in find_or_create_wa_session (no eligible agents)
      return
    end

    case session.wa_state
    when nil
      handle_new_session(session)
    when "awaiting_agent_selection"
      handle_agent_selection(session)
    when "awaiting_fund_selection"
      handle_fund_selection(session)
    when "active"
      handle_active_session(session)
    end
  rescue StandardError => e
    Rails.logger.error "[WhatsappChatDispatcher] error for user=#{@user_id}: #{e.class} — #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end

  private

  # ─── Session management ────────────────────────────────────────────────────

  def find_or_create_wa_session
    session = AgentChatSession
              .joins(:support_agent)
              .where(analyst_id: @user.id, channel: "whatsapp", status: "active")
              .where("agent_chat_sessions.updated_at > ?", SESSION_TIMEOUT.ago)
              .order(updated_at: :desc)
              .first

    return session if session

    # Create a skeleton session without a support_agent; we'll assign it after
    # agent selection. Use the first enabled chat agent as a placeholder because
    # the association is NOT NULL. We'll overwrite it when selection is made.
    placeholder_agent = eligible_agents.first
    @agent = placeholder_agent
    return send_no_assistant_available_message if placeholder_agent.nil?

    AgentChatSession.create!(
      analyst: @user,
      support_agent: placeholder_agent,
      channel: "whatsapp",
      status: "active",
      wa_state: nil,
      wa_metadata: {}
    )
  end

  # ─── State handlers ────────────────────────────────────────────────────────

  # Called when a session is brand-new (wa_state = nil).
  def handle_new_session(session)
    agents = eligible_agents
    if agents.empty?
      send_message("Sorry, no AI assistants are available for your account at this time.")
      return
    end

    if agents.size == 1
      auto_select_agent(session, agents.first)
    else
      present_agent_menu(session, agents)
    end
  end

  # Called when wa_state = "awaiting_agent_selection".
  def handle_agent_selection(session)
    if MENU_KEYWORD_REGEX.match?(@message)
      reset_session(session)
      return handle_new_session(session)
    end

    options = (session.wa_metadata || {})["agent_options"] || {}
    choice  = options[@message&.strip]

    unless choice
      send_message("#{build_agent_menu_text(options)}\n\nPlease reply with a valid number.")
      return
    end

    @agent = SupportAgent.find_by(id: choice["support_agent_id"])
    unless @agent
      Rails.logger.error "[WhatsappChatDispatcher] Invalid agent selection for user=#{@user_id}; message - #{@message}"
      send_message("Sorry, we couldn't find that agent. Please try again.")
      return
    end

    session.update!(support_agent: @agent)

    if @agent.agent_type == "LpAssistantAgent"
      transition_to_fund_selection(session)
    else
      session.update!(wa_state: "active")

      # Transform the selection message to something meaningful before processing
      # This prevents the AI from saying "I don't understand '2'"
      @message = "I'd like assistance with the platform."
      handle_message(session)
    end
  end

  # Called when wa_state = "awaiting_fund_selection".
  def handle_fund_selection(session)
    if MENU_KEYWORD_REGEX.match?(@message)
      reset_session(session)
      return handle_new_session(session)
    end

    metadata = session.wa_metadata || {}
    fund_options = metadata["fund_options"]

    unless fund_options
      # First pass — present fund menu
      present_fund_menu(session)
      return
    end

    choice = fund_options[@message]

    unless choice
      send_message("#{build_fund_menu_text(fund_options)}\n\nPlease reply with a valid number.")
      return
    end

    metadata["selected_fund_id"] = choice["fund_id"]
    session.update!(wa_state: "active", wa_metadata: metadata)

    send_message("Great! I'll answer your questions about *#{choice['fund_name']}*. What would you like to know?")
  end

  # Called when wa_state = "active".
  def handle_active_session(session)
    if MENU_KEYWORD_REGEX.match?(@message)
      reset_session(session)
      return handle_new_session(session)
    end

    metadata = session.wa_metadata || {}
    if metadata["awaiting_feedback_notes"]
      record_negative_feedback_notes(session, metadata)
      reset_session(session)
      return
    end

    if metadata["awaiting_feedback"] && handle_feedback_reply(session, metadata)
      return
      # Non-feedback reply — fall through to process as a new message
    end

    if GOODBYE_KEYWORD_REGEX.match?(@message)
      send_message("Thanks for chatting! If you have more questions, just send another message.")
      support_agent = session.support_agent
      send_feedback_prompt(session) if support_agent.agent_type == "CustomerSupportAgent"
      return
    end

    # Check for pending feedback response first

    handle_message(session)
  end

  # ─── Core message processing ────────────────────────────────────────────────

  def handle_message(session)
    support_agent = session.support_agent
    chattable = resolve_chattable(session, support_agent)

    if support_agent.agent_type == "LpAssistantAgent" && chattable.nil?
      session.update!(wa_state: "awaiting_fund_selection")
      present_fund_menu(session)
      return
    end

    result = GenericChatAgent.call(
      support_agent_id: support_agent.id,
      analyst_id: @user.id,
      target: chattable,
      user_message: @message,
      channel: "whatsapp"
    )

    ai_response = result[:ai_response].to_s
    formatted   = WhatsappResponseFormatter.format(ai_response)

    send_message(formatted)
  end

  def resolve_chattable(session, support_agent)
    if support_agent.agent_type == "LpAssistantAgent"
      fund_id = (session.wa_metadata || {})["selected_fund_id"]
      Fund.find_by(id: fund_id)
    else
      support_agent
    end
  end

  # ─── Agent selection helpers ─────────────────────────────────────────────

  def eligible_agents
    @eligible_agents ||= begin
      all_agents = SupportAgent.for_user(@user).enabled.select(&:chat_enabled?)
      all_agents.select { |agent| agent_accessible_by_user?(agent) }
    end
  end

  def agent_accessible_by_user?(agent)
    case agent.agent_type
    when "LpAssistantAgent"
      InvestorAccess.exists?(entity_id: agent.entity_id, user_id: @user.id, approved: true)
    when "CustomerSupportAgent"
      true
    else
      false
    end
  end

  def auto_select_agent(session, agent)
    @agent = agent
    session.update!(support_agent: agent)

    if agent.agent_type == "LpAssistantAgent"
      transition_to_fund_selection(session)
    else
      session.update!(wa_state: "active")
      handle_message(session)
    end
  end

  def present_agent_menu(session, agents)
    options = {}
    agent_types_shown = Set.new
    idx = 1
    agents.each do |agent|
      label = agent.agent_type == "LpAssistantAgent" ? "Investment queries (view fund data, SOA, performance)" : "Platform support (how-to questions, troubleshooting)"

      next if agent_types_shown.include?(agent.agent_type)

      # we can add entity name here for distinction
      options[idx.to_s] = { "agent_type" => agent.agent_type, "support_agent_id" => agent.id, "label" => label }
      idx += 1
      agent_types_shown.add(agent.agent_type)
    end

    metadata = (session.wa_metadata || {}).merge("agent_options" => options)
    session.update!(wa_state: "awaiting_agent_selection", wa_metadata: metadata)

    send_message("Hi #{@user.first_name}! How can I help you today?\n\n#{build_agent_menu_text(options)}\n\nReply with the number. You can also type *menu* at any time to see this menu again.")
  end

  def build_agent_menu_text(options)
    options.map { |num, opt| "#{num} - #{opt['label']}" }.join("\n")
  end

  # ─── Fund selection helpers ───────────────────────────────────────────────

  def transition_to_fund_selection(session)
    funds = accessible_funds
    if funds.empty?
      send_message("You don't appear to have access to any funds. Please contact your fund administrator.")
      return
    end

    if funds.size == 1
      fund = funds.first
      metadata = (session.wa_metadata || {}).merge("selected_fund_id" => fund.id)
      session.update!(wa_state: "active", wa_metadata: metadata)
      send_message("I'll answer your questions about *#{fund.name}*. What would you like to know?")
    else
      present_fund_menu(session, funds)
    end
  end

  def present_fund_menu(session, funds = nil)
    funds ||= accessible_funds
    options = {}
    funds.each_with_index do |fund, idx|
      options[(idx + 1).to_s] = { "fund_id" => fund.id, "fund_name" => fund.name }
    end

    metadata = (session.wa_metadata || {}).merge("fund_options" => options)
    session.update!(wa_state: "awaiting_fund_selection", wa_metadata: metadata)

    send_message("Which fund would you like to query?\n\n#{build_fund_menu_text(options)}\n\nReply with the number.")
  end

  def build_fund_menu_text(options)
    options.map { |num, opt| "#{num} - #{opt['fund_name']}" }.join("\n")
  end

  def accessible_funds
    @funds ||= Fund.for_investor(@user)
                   .distinct
                   .to_a
    @funds
  end

  # ─── Feedback helpers ─────────────────────────────────────────────────────

  def send_feedback_prompt(session)
    metadata = (session.wa_metadata || {}).merge("awaiting_feedback" => true)
    session.update!(wa_metadata: metadata)
    send_message("Was this helpful? Reply *YES* or *NO*")
  end

  # @return [Boolean] true if message was handled as feedback, false if it should fall through
  def handle_feedback_reply(session, metadata)
    positive = /\A\s*(yes|👍|y)\s*\z/i.match?(@message)
    negative = /\A\s*(no|👎|n)\s*\z/i.match?(@message)

    if positive
      record_feedback(session, "positive", nil)
      clear_feedback_flags(session, metadata)
      send_message("Thank you for your feedback!")
      reset_session(session)
      return true
    end

    if negative
      new_metadata = metadata.merge("awaiting_feedback" => false, "awaiting_feedback_notes" => true)
      session.update!(wa_metadata: new_metadata)
      send_message("What could be improved?")
      return true
    end

    # Not a feedback reply — clear the flag so message is processed normally
    clear_feedback_flags(session, metadata)
    false
  end

  def record_negative_feedback_notes(session, metadata)
    record_feedback(session, "negative", @message)
    clear_feedback_flags(session, metadata)
    send_message("Thank you for your feedback!")
  end

  def record_feedback(session, rating, notes)
    last_assistant_msg = session.agent_chat_messages
                                .where(role: "assistant", channel: "whatsapp")
                                .order(created_at: :desc)
                                .first
    return unless last_assistant_msg

    feedback = last_assistant_msg.feedback || last_assistant_msg.build_feedback(
      entity_id: session.support_agent.entity_id,
      user: @user
    )
    feedback.update!(rating: rating, notes: notes, channel: "whatsapp")
  end

  def clear_feedback_flags(session, metadata)
    new_metadata = metadata.except("awaiting_feedback", "awaiting_feedback_notes")
    session.update!(wa_metadata: new_metadata)
  end

  # ─── Session reset ────────────────────────────────────────────────────────

  def reset_session(session)
    session.update!(
      wa_state: nil,
      wa_metadata: {},
      support_agent: eligible_agents.first || session.support_agent
    )
  end

  # ─── WATI delivery ────────────────────────────────────────────────────────

  def send_message(text)
    @entity_setting ||= if @agent.present?
                          @agent.entity&.entity_setting
                        else
                          @user.entity.entity_setting
                        end
    WhatsappGeneralNotification.send_session_message(
      { conversation_id: @conversation_id, whatsapp_number: @user.phone_with_call_code, message: text },
      endpoint: @entity_setting.fetch_whatsapp_endpoint,
      token: @entity_setting.fetch_whatsapp_token
    )
  end

  def send_unrecognised_user_message
    # We don't know which WATI endpoint to use for truly unknown users, so we log and drop.
    Rails.logger.warn "[WhatsappChatDispatcher] Unrecognized user=#{@user_id} entity=#{@user&.entity_id}"
    send_message("Sorry, we couldn't recognize your account. Please contact support for assistance.") if @user.present?
    nil
  end

  def send_no_assistant_available_message
    Rails.logger.warn "[WhatsappChatDispatcher] No eligible agents for user=#{@user_id} entity=#{@user&.entity_id}"
    send_message("Sorry, no AI assistants are available for your account at this time.")
    nil
  end
end
