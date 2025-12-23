class AssistantsController < ApplicationController
  def show
    authorize :assistant, :show?

    if params[:assistant_type].present?
      assistant_class = case params[:assistant_type]
                        when 'portfolio_company'
                          'PortfolioCompanyAssistant'
                        else
                          'FundAssistant'
                        end

      if params[:new].present?
        ActiveRecord::Base.connected_to(role: :writing) do
          @chat = Chat.create!(
            user: current_user,
            entity_id: current_user.entity_id,
            assistant_type: assistant_class,
            owner: current_user, # Default owner to user, can be overridden
            enable_broadcast: false,
            model_id: PortfolioCompanyAssistant::AI_MODEL,
            name: "#{assistant_class.humanize} Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
          )
        end
      elsif params[:chat_id].present?
        @chat = Chat.find_by(id: params[:chat_id], entity_id: current_user.entity_id, assistant_type: assistant_class)
      else
        @chat = Chat.where(
          user: current_user,
          entity_id: current_user.entity_id,
          assistant_type: assistant_class
        ).order(created_at: :desc).first
      end

      Rails.logger.debug { "Loaded chat: #{@chat.id}" } if @chat
      @messages = @chat.messages.where(role: %w[user assistant]).order(created_at: :asc) if @chat
    end
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
end
