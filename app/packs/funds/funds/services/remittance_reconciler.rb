class RemittanceReconciler < Trailblazer::Operation
  step :init
  step :upload_csv
  step :verify_remittance
  step :create_remittance_payment
  step :save
  step :cleanup
  left :handle_errors, Output(:failure) => End(:failure)

  def init(ctx, capital_remittance:, **)
    log_debug("RemittanceReconciler for #{capital_remittance}")
    # Initialize OpenAI client
    open_ai_client = OpenAI::Client.new(access_token: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })
    # Save the client for future reference
    ctx[:open_ai_client] = open_ai_client
    true
  end

  def log_debug(message)
    Rails.logger.debug { message }
  end

  def upload_csv(ctx, open_ai_client:, csv_file_path:, **)
    # Upload the CSV file to OpenAI
    file_id = upload_csv_to_openai(open_ai_client, csv_file_path)
    if file_id
      puts { "File uploaded successfully. File ID: #{file_id}" }
      # Save the file ID for future reference
      ctx[:file_id] = file_id
      true
    else
      log_debug("File upload failed.")
      false
    end
  end

  def verify_remittance(ctx, open_ai_client:, file_id:, capital_remittance:, **)
    # Setup the assistant for the remittance reconciler
    setup_assistant(ctx, open_ai_client, [file_id])
    # Perform semantic search on the uploaded CSV file
    query = "Check the csv file and extract the amount paid by #{capital_remittance.investor.investor_name}?"
    answer = semantic_search(ctx, open_ai_client, query)
    if answer
      puts { "Answer: #{answer}" }
      ctx[:answer] = answer
      true
    else
      log_debug("Semantic search failed.")
      false
    end
  end

  def create_remittance_payment(ctx, answer:, capital_remittance:, **)
    Rails.logger.debug { "Answer: #{answer} class: #{answer.class}" }
    # Sometimes the answer is returned as an array
    answer = answer[0] if answer.instance_of?(Array)
    # Create a remittance payment based on the answer
    if answer["paid"] == true && answer["amount"].present?
      amount_cents = answer["amount"].to_f
      payment_date = answer["payment_date"]
      reference_no = answer["reference"]
      capital_remittance_payment = capital_remittance.capital_remittance_payments.build(fund_id: capital_remittance.fund_id, entity_id: capital_remittance.entity_id, amount_cents:, payment_date:, reference_no:, notes: "Remittance reconciled by AI")
      ctx[:capital_remittance_payment] = capital_remittance_payment
    else
      false
    end
  end

  def save(_ctx, capital_remittance:, capital_remittance_payment:, **)
    capital_remittance.transaction do
      capital_remittance_payment.save
      capital_remittance.save
    end
    true
  end

  def handle_errors(ctx, open_ai_client:, **)
    cleanup(ctx, open_ai_client:)
  end

  def cleanup(ctx, open_ai_client:, **)
    open_ai_client.assistants.delete(id: ctx[:assistant_id]) if ctx[:assistant_id]
    true
  end

  private

  def setup_assistant(ctx, client, file_ids)
    response = client.assistants.create(
      parameters: {
        model: "gpt-4o",
        name: "RemittanceReconciler",
        description: nil,
        instructions: "You are a remittance reconciler. You need to verify the remittance payments made by investors. You return data in json format without any additional formatting or comments. Ex {investor_name: 'John Doe', paid: true, amount: 1000, payment_date: '2023-12-10', reference: 'INV-1234'}. You only return data in the csv file, and do not create any data.",
        tools: [
          { type: "code_interpreter" }
        ],
        tool_resources: {
          code_interpreter: {
            file_ids:
          }
        },
        metadata: { my_internal_version_id: "1.0.0" }
      }
    )

    assistant_id = response["id"]
    # Save the assistant for future reference
    ctx[:assistant] = client.assistants.retrieve(id: assistant_id)
    ctx[:assistant_id] = assistant_id
  end

  def log_debug(message)
    Rails.logger.debug { message }
  end

  def upload_csv_to_openai(open_ai_client, file_path)
    response = open_ai_client.files.upload(parameters: { file: file_path, purpose: "assistants" })
    Rails.logger.debug { "File Upload Response: #{response}" }
    response["id"]
  rescue StandardError => e
    Rails.logger.error "OpenAI File Upload Error: #{e.message}"
    nil
  end

  def semantic_search(ctx, open_ai_client, query)
    # Create thread
    response = open_ai_client.threads.create # NOTE: Once you create a thread, there is no way to list it
    # or recover it currently (as of 2023-12-10). So hold onto the `id`
    thread_id = response["id"]

    open_ai_client.messages.create(thread_id:,
                                   parameters: {
                                     role: "user",
                                     content: query
                                   })["id"]

    # Create a run to enqueue the messages with the LLM                                   
    response = open_ai_client.runs.create(thread_id:,
                                          parameters: {
                                            assistant_id: ctx[:assistant_id]
                                          })

    run_id = response["id"]
    # Now we wait for the LLM to complete
    wait_for_semantic_search(open_ai_client, run_id, thread_id)
    
    messages = open_ai_client.messages.list(thread_id:)
    Rails.logger.debug "Messages on thread:"
    Rails.logger.debug messages

    ctx[:messages] = messages
    begin
      json = messages["data"][0]["content"][0]["text"]["value"]
      JSON.parse(json)
    rescue StandardError
      nil
    end
  rescue OpenAI::Error => e
    Rails.logger.error "OpenAI Semantic Search Error: #{e.message}"
    open_ai_client.assistants.delete(id: ctx[:assistant_id]) if ctx[:assistant_id]
  end

  def wait_for_semantic_search(open_ai_client, run_id, thread_id)
    loop do
      response = open_ai_client.runs.retrieve(id: run_id, thread_id:)
      status = response['status']

      case status
      when 'queued', 'in_progress', 'cancelling'
        Rails.logger.debug 'Sleeping'
        sleep 1 # Wait one second and poll again
      when 'completed'
        Rails.logger.debug { "Run completed with response: #{response}" }
        break # Exit loop and report result to user
      when 'requires_action'
        # Handle tool calls (see below)
      when 'cancelled', 'failed', 'expired'
        Rails.logger.debug response['last_error'].inspect
        break # or `exit`
      else
        Rails.logger.debug { "Unknown status response: #{status}" }
      end
    end

  end
end
