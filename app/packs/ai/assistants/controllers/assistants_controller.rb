class AssistantsController < ApplicationController
  # Record classes a chat is allowed to be "owned by". Anything the LLM/browser-supplied
  # owner_type resolves to outside this list is rejected before it ever reaches constantize.
  ALLOWED_CHAT_OWNER_TYPES = %w[Investor Fund CapitalCommitment].freeze

  def show
    authorize :assistant, :show?

    # Handle the generate_slides action when requested via the collection route
    return generate_slides if params[:id] == 'generate_slides'

    return if params[:assistant_type].blank?

    @chat = find_or_create_chat
    return unless @chat

    Rails.logger.debug { "Loaded chat: #{@chat.id}" }
    @assistant_description = assistant_class.constantize::DESCRIPTION
    @messages = @chat.messages.where(role: %w[user assistant]).order(created_at: :asc)
    @chats = Chat.where(user: current_user, entity_id: current_user.entity_id, assistant_type: assistant_class).order(created_at: :desc)
  end

  def efficiency_report
    authorize :assistant, :show?

    @chat = Chat.find_by(id: params[:chat_id], entity_id: current_user.entity_id)
    @all_messages = @chat.messages.includes(:tool_calls).order(created_at: :asc)
    @tool_calls = ToolCall.joins(message: :chat)
                          .where(chats: { entity_id: current_user.entity_id, id: @chat.id })

    # Calculate some stats for the report
    @stats = {
      total_calls: @tool_calls.length,
      missing_limit: @tool_calls.count { |tc| tc.name.start_with?('list_') && tc.arguments['limit'].blank? },
      total_input_tokens: @all_messages.sum(:input_tokens),
      total_output_tokens: @all_messages.sum(:output_tokens)
    }

    # Gemini Pricing (default as fallback)
    # Input: $0.50 / 1M tokens
    # Output: $3.00 / 1M tokens
    input_rate = 0.50
    output_rate = 3.00

    if @chat.model&.pricing.present?
      pricing = @chat.model.pricing["text_tokens"]&.fetch("standard", {})
      input_rate = pricing["input_per_million"] || input_rate
      output_rate = pricing["output_per_million"] || output_rate
    end

    @input_rate = input_rate
    @output_rate = output_rate

    input_cost = (@stats[:total_input_tokens] / 1_000_000.0) * input_rate
    output_cost = (@stats[:total_output_tokens] / 1_000_000.0) * output_rate
    @stats[:total_cost_usd] = input_cost + output_cost

    render "efficiency_report"
  end

  def ask
    authorize :assistant, :ask?
    query = params.require(:query).to_s
    chat_id = params.require(:chat_id)
    assistant_type = params[:assistant_type] || 'fund'
    request_id = SecureRandom.hex(12)

    AssistantQueryJob.perform_later(current_user.id, chat_id, request_id, query, assistant_type)

    render partial: "ask_frame", locals: { query: query, response: nil, request_id: request_id, error: nil }
  end

  def transcribe
    authorize :assistant, :transcribe?
    audio = params.require(:audio)
    chat_id = params.require(:chat_id)

    Tempfile.create(["voice", File.extname(audio.original_filename.presence || ".webm")]) do |f|
      f.binmode
      f.write(audio.read)
      f.flush

      transcription = RubyLLM.transcribe(f.path) # RubyLLM transcription
      query = transcription.text.to_s
      assistant_type = params[:assistant_type] || 'fund'
      request_id = SecureRandom.hex(12)

      AssistantQueryJob.perform_later(current_user.id, chat_id, request_id, query, assistant_type)

      render partial: "ask_frame", locals: { query: query, response: nil, request_id: request_id, error: nil }
    end
  end

  def generate_slides
    authorize :assistant, :show?

    @chat_id = params.require(:chat_id)
    force_generate = params[:generate] == 'true'

    existing = (AiPresentation.find_by(chat_id: @chat_id, entity_id: current_user.entity_id) unless force_generate)

    respond_to do |format|
      format.json do
        if existing
          render json: { html: existing.content_html, status: "ready" }
        else
          GenerateSlidesJob.perform_later(current_user.id, @chat_id, force_generate: force_generate)
          render json: { status: "queued" }, status: :accepted
        end
      end

      format.html do
        if existing
          @slides_html = existing.content_html
        else
          GenerateSlidesJob.perform_later(current_user.id, @chat_id, force_generate: force_generate)
        end

        # Avoid calling Devise helpers in ActionController::Base.renderer contexts.
        @slides_user = current_user

        render layout: "presentation", template: "/assistants/generate_slides"
      end
    end
  rescue StandardError => e
    Rails.logger.error("Slide generation failed: #{e.message}")
    render json: { error: "Failed to generate slides: #{e.message}" }, status: :unprocessable_entity
  end

  private

  # Resolves owner_type/owner_id to a record the *current user* is actually authorized to
  # see. A bare `owner_type.constantize.find_by(id: owner_id)` would let any authenticated
  # user open a chat against an arbitrary id -- including a record belonging to a different
  # entity/tenant -- since nothing checked it was theirs. That record's #to_s is written
  # into the chat name below and rendered back to the requesting user, so an unscoped lookup
  # here is a direct cross-tenant information leak, not just a theoretical gap.
  def find_chat_owner(owner_type, owner_id)
    return nil if owner_type.blank? || owner_id.blank?
    return nil unless ALLOWED_CHAT_OWNER_TYPES.include?(owner_type)

    Pundit.policy_scope(current_user, owner_type.constantize).find_by(id: owner_id)
  end

  def find_or_create_chat
    return Chat.find_by(id: params[:chat_id], entity_id: current_user.entity_id, assistant_type: assistant_class) if params[:new].blank? && params[:chat_id].present?

    owner = find_chat_owner(params[:owner_type], params[:owner_id])

    if %w[PortfolioCompanyAssistant CapitalCommitmentAssistant SpecificFundAssistant].include?(assistant_class)
      owner ||= current_user
    else
      owner = current_user
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      chat = if params[:new].present?
               Chat.new(
                 user: current_user,
                 entity_id: current_user.entity_id,
                 assistant_type: assistant_class,
                 owner: owner
               )
             else
               Chat.find_or_initialize_by(
                 user: current_user,
                 entity_id: current_user.entity_id,
                 assistant_type: assistant_class,
                 owner: owner
               )
             end

      if chat.new_record?
        chat.assign_attributes(
          enable_broadcast: false,
          model: PortfolioCompanyAssistant::AI_MODEL,
          name: "#{owner} Chat #{I18n.l(Time.zone.now, format: :default)}"
        )
        chat.save!
      end
      chat
    end
  end

  def assistant_initials
    case assistant_class
    when 'PortfolioCompanyAssistant' then 'PCA'
    when 'CapitalCommitmentAssistant' then 'CCA'
    when 'SpecificFundAssistant' then 'SFA'
    else 'FA'
    end
  end

  def assistant_class
    @assistant_class ||= params[:assistant_type]
  end
end
