class RemittanceReconciler < Trailblazer::Operation
  step :init
  step :upload_csv
  step :verify_remittance
  step :create_remittance_payment
  step :save
  step :cleanup
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

    setup_assistant(ctx, open_ai_client, [file_id])
    # Perform semantic search on the uploaded CSV file
    query = "What is the amount paid by #{capital_remittance.investor.investor_name}?"
    answer = semantic_search(ctx, open_ai_client, query)
    if answer
      puts { "Answer: #{answer}" }
    else
      Rails.logger.debug "Semantic search failed."
    end

    ctx[:answer] = answer

    true
  end

  def cleanup(ctx, open_ai_client:, **)
    # Clean up any temporary files
    open_ai_client.assistants.delete(id: ctx[:assistant_id]) if ctx[:assistant_id]
    true
  end

  def setup_assistant(ctx, client, file_ids)
    response = client.assistants.create(
                  parameters: {
                      model: "gpt-4o",
                      name: "RemittanceReconciler",
                      description: nil,
                      instructions: "You are a remittance reconciler. You need to verify the remittance payments made by investors.",
                      tools: [
                          { type: "code_interpreter" }
                      ],
                      tool_resources: {
                        code_interpreter: {
                          file_ids: 
                        }
                      },
                      "metadata": { my_internal_version_id: "1.0.0" }
                  })

    assistant_id = response["id"]
    # Save the assistant for future reference
    ctx[:assistant] = client.assistants.retrieve(id: assistant_id)
    ctx[:assistant_id] = assistant_id
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

  def upload_csv_to_openai(open_ai_client, file_path)
    response = open_ai_client.files.upload(parameters: { file: file_path, purpose: "assistants" })
    puts "File Upload Response: #{response}"
    file_id = response["id"]
    file_id
  rescue StandardError => e
    Rails.logger.error "OpenAI File Upload Error: #{e.message}"
    nil
  end

  def semantic_search(ctx, open_ai_client, query)
    # Create thread
    response = open_ai_client.threads.create # Note: Once you create a thread, there is no way to list it
    # or recover it currently (as of 2023-12-10). So hold onto the `id`
    thread_id = response["id"]

    message_id = open_ai_client.messages.create(thread_id: thread_id,
                                        parameters: {
                                          role: "user", 
                                          content: query
                                        })["id"]


    response = open_ai_client.runs.create(thread_id: thread_id,
                                          parameters: {
                                              assistant_id: ctx[:assistant_id],
                                              max_prompt_tokens: 256,
                                              max_completion_tokens: 16,
                                              stream: proc do |chunk, _bytesize|
                                                print chunk.dig("delta", "content", 0, "text", "value") if chunk["object"] == "thread.message.delta"
                                              end
                                          })
    run_id = response['id']
    puts response
    sleep(20)


    # while true do
    #   response = open_ai_client.runs.retrieve(id: run_id, thread_id: thread_id)
    #   status = response['status']
    #   messages = open_ai_client.messages.list(thread_id: thread_id)
    #   puts messages

    #   case status
    #   when 'queued', 'in_progress', 'cancelling'
    #     puts 'Sleeping'
    #     sleep 2 # Wait one second and poll again
    #   when 'completed'
    #     break # Exit loop and report result to user
    #   when 'requires_action'
    #     # Handle tool calls (see below)
    #     puts response['action']
    #     break
    #   when 'cancelled', 'failed', 'expired'
    #     puts response['last_error'].inspect
    #     break # or `exit`
    #   else
    #     puts "Unknown status response: #{status}"
    #   end
    # end

    # messages = client.messages.list(thread_id: thread_id, parameters: { order: 'asc' })

    # puts messages

  rescue OpenAI::Error => e
    Rails.logger.error "OpenAI Semantic Search Error: #{e.message}"
    open_ai_client.assistants.delete(id: ctx[:assistant_id]) if ctx[:assistant_id]
  end
end
