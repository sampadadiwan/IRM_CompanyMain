class AssistantsController < ApplicationController
  def show
    authorize :assistant, :show?

    # Handle the generate_slides action when requested via the collection route
    return generate_slides if params[:id] == 'generate_slides'

    return if params[:assistant_type].blank?

    @chat = find_or_create_chat
    return unless @chat

    Rails.logger.debug { "Loaded chat: #{@chat.id}" }
    @messages = @chat.messages.where(role: %w[user assistant]).order(created_at: :asc)
    @chats = Chat.where(user: current_user, entity_id: current_user.entity_id, assistant_type: assistant_class).order(created_at: :desc)
  end

  def ask
    authorize :assistant, :ask?
    query = params.require(:query).to_s
    assistant_type = params[:assistant_type] || 'fund'
    request_id = SecureRandom.hex(12)

    AssistantQueryJob.perform_later(current_user.id, request_id, query, assistant_type)

    render partial: "ask_frame", locals: { query: query, response: nil, request_id: request_id, error: nil }
  end

  def transcribe
    authorize :assistant, :transcribe?
    audio = params.require(:audio)

    Tempfile.create(["voice", File.extname(audio.original_filename.presence || ".webm")]) do |f|
      f.binmode
      f.write(audio.read)
      f.flush

      transcription = RubyLLM.transcribe(f.path) # RubyLLM transcription
      query = transcription.text.to_s
      assistant_type = params[:assistant_type] || 'fund'
      request_id = SecureRandom.hex(12)

      AssistantQueryJob.perform_later(current_user.id, request_id, query, assistant_type)

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
    if params[:new].present?
      create_chat
    elsif params[:chat_id].present?
      Chat.find_by(id: params[:chat_id], entity_id: current_user.entity_id, assistant_type: assistant_class)
    else
      @chat = Chat.where(user: current_user, entity_id: current_user.entity_id, assistant_type: assistant_class)
                  .order(created_at: :desc).first
      @chat || create_chat
    end
  end

  def create_chat
    commitment = CapitalCommitment.find_by(id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?
    portfolio_company = Investor.find_by(id: params[:portfolio_company_id]) if params[:portfolio_company_id].present?

    owner = commitment || portfolio_company || current_user

    ActiveRecord::Base.connected_to(role: :writing) do
      Chat.create!(
        user: current_user,
        entity_id: current_user.entity_id,
        assistant_type: assistant_class,
        owner: owner,
        enable_broadcast: false,
        model_id: PortfolioCompanyAssistant::AI_MODEL,
        name: "#{assistant_initials} Chat #{I18n.l(Time.zone.now, format: :default)}"
      )
    end
  end

  def assistant_initials
    case assistant_class
    when 'PortfolioCompanyAssistant' then 'PCA'
    when 'CapitalCommitmentAssistant' then 'CCA'
    else 'FA'
    end
  end

  def assistant_class
    @assistant_class ||= case params[:assistant_type]
                         when 'portfolio_company' then 'PortfolioCompanyAssistant'
                         when 'capital_commitment' then 'CapitalCommitmentAssistant'
                         else 'FundAssistant'
                         end
  end
end
