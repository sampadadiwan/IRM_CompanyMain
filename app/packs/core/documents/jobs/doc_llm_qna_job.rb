class DocLlmQnaJob < ApplicationJob
  def perform(model_class, model_id, user_id, document_ids: nil)
    # Load the model Ex specific Investor or Kyc
    model = model_class.constantize.find(model_id)
    Chewy.strategy(:sidekiq) do
      send_notification("Document QnA started for #{model}. This will take time so please be patient..", user_id, "info")
      docs = if document_ids.present?
               # Specific documents
               model.documents.where(id: document_ids)
             else
               # All documents which have doc_questions
               model.documents.where(name: model.document_names_for_validation)
             end

      # For each document, get the questions and send it to the QnA service
      docs.each do |document|
        answers_from_assistant(model, document)
        # answers_from_api(model, document)
        send_notification("Document #{document.name} QnA completed for #{model}", user_id, "info")
      end
    end
  end

  def answers_from_assistant(model, document)
    assistant = AiAssistant.new(nil, AiAssistant::QNA_INSTRUCTIONS)
    # Get the questions for this document
    questions = model.doc_questions_for(document)
    assistant.addDocAsImage(document)
    results = questions.map do |question|
      # JSON.parse(assistant.query(question))
      assistant.query(question)
    end
    document.qna = results.to_json
    document.save
  end

  def answers_from_api(model, document)
    # Get the questions for this document
    questions = model.doc_questions_for(document)
    # Send the questions to the QnA service
    response = HTTParty.post(
      "http://localhost:8000/docs-qna/",
      headers: {
        'Content-Type' => 'application/json'
      },
      body: {
        api_key: Rails.application.credentials["OPENAI_API_KEY"],
        file_url: document.file.url,
        question: questions.join("\n")
      }.to_json
    )
    # Parse the response and save the answers
    document.qna = JSON.parse(response.body)["answer"]
    document.save
  end
end
