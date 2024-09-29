class RemittanceReconciler < Trailblazer::Operation
  step :init
  step :upload_csv
  step :verify_remittance
  step :create_remittance_payment
  step :save
  left :handle_errors, Output(:failure) => End(:failure)

  def init(ctx, capital_remittance:, **)
    Rails.logger.debug { "RemittanceReconciler for #{capital_remittance}" }
    open_ai_client = OpenAI::Client.new(access_token: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "gpt-4o" })
    ctx[:open_ai_client] = open_ai_client
    true
  end

  def upload_csv(ctx, open_ai_client:, csv_file_path:, **)
    # Read the CSV file
    # csv = CSV.read(csv_file.path, headers: true)
    # ctx[:csv] = csv

    file_id = upload_csv_to_openai(open_ai_client, csv_file_path)
    if file_id
      puts { "File uploaded successfully. File ID: #{file_id}" }
    else
      Rails.logger.debug "File upload failed."
    end

    ctx[:file_id] = file_id

    true
  end

  def verify_remittance(ctx, open_ai_client:, file_id:, capital_remittance:, **)
    # Perform semantic search on the uploaded CSV file
    query = "What is the amount paid by #{capital_remittance.investor.investor_name}?"
    answer = semantic_search(open_ai_client, file_id, query)
    if answer
      puts { "Answer: #{answer}" }
    else
      Rails.logger.debug "Semantic search failed."
    end

    ctx[:answer] = answer

    true
  end

  def create_remittance_payment(ctx, answer:, capital_remittance:, **)
    # Create a remittance payment based on the answer
    amount = answer.to_f
    capital_remittance_payment = capital_remittance.capital_remittance_payments.build(amount:)
    ctx[:capital_remittance_payment] = capital_remittance_payment
  end

  def save(_ctx, capital_remittance:, capital_remittance_payment:, **)
    capital_remittance.transaction do
      # capital_remittance_payment.save
      # capital_remittance.save
    end
    true
  end

  def handle_errors(ctx, **); end

  private

  def upload_csv_to_openai(_open_ai_client, file_path)
    # Prepare the file for upload using Faraday::UploadIO
    file = Faraday::UploadIO.new(file_path, 'text/csv')

    # Make a multipart/form-data POST request to /v1/files
    response = client.connection.post('/v1/files') do |req|
      req.headers['Content-Type'] = 'multipart/form-data'
      req.body = {
        file:,
        purpose: 'answers' # 'answers' is used for semantic search and Q&A
      }
    end

    # Parse the response
    if response.status == 200 || response.status == 201
      JSON.parse(response.body)
    else
      Rails.logger.error "OpenAI File Upload Failed: #{response.status} - #{response.body}"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "OpenAI File Upload Error: #{e.message}"
    nil
  end

  def semantic_search(open_ai_client, file_id, query)
    response = open_ai_client.answers(
      parameters: {
        # search_model: "ada", # Efficient model for semantic search
        # model: "davinci", # Model used to generate answers
        question: query,
        file: file_id,
        examples_context: "Provide answers using the information from the CSV file.",
        examples: [
          ["What is the amount paid by Client123?", "$X"]
        ],
        max_tokens: 100,
        temperature: 0
      }
    )

    # Extract and return the most relevant answer
    response["answers"].first
  rescue OpenAI::Error => e
    Rails.logger.error "OpenAI Semantic Search Error: #{e.message}"
    nil
  end
end
