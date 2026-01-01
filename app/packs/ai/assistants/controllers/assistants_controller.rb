class AssistantsController < ApplicationController
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

  def find_or_create_chat
    return Chat.find_by(id: params[:chat_id], entity_id: current_user.entity_id, assistant_type: assistant_class) if params[:new].blank? && params[:chat_id].present?

    owner = params[:owner_type].constantize.find_by(id: params[:owner_id]) if params[:owner_type].present? && params[:owner_id].present?

    if ["PortfolioCompanyAssistant", "CapitalCommitmentAssistant", "SpecificFundAssistant"].include?(assistant_class)
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
          model_id: PortfolioCompanyAssistant::AI_MODEL,
          name: "#{assistant_initials} Chat #{I18n.l(Time.zone.now, format: :default)}"
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
    @assistant_class ||= case params[:assistant_type]
                         when 'portfolio_company' then 'PortfolioCompanyAssistant'
                         when 'capital_commitment' then 'CapitalCommitmentAssistant'
                         when 'specific_fund' then 'SpecificFundAssistant'
                         else 'FundAssistant'
                         end
  end
end
