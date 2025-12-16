class AssistantsController < ApplicationController
  def show
    authorize :assistant, :show?
  end

  def ask
    authorize :assistant, :ask?
    query = params.require(:query).to_s
    request_id = SecureRandom.hex(12)

    AssistantQueryJob.perform_later(current_user.id, request_id, query)

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
      request_id = SecureRandom.hex(12)

      AssistantQueryJob.perform_later(current_user.id, request_id, query)

      render partial: "ask_frame", locals: { query: query, response: nil, request_id: request_id, error: nil }
    end
  end
end
