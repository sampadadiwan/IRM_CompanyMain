# == Service: KpiXlExtractionEngine
# Processes an MIS Excel file and extracts KPI records per tenant and company
class KpiXlExtractionEngine
  def initialize(file_path:, entity_id:, portfolio_company_id:)
    @file_path = file_path
    @entity_id = entity_id
    @portfolio_company_id = portfolio_company_id
  end

  # Main entry point to extract KPI records
  def process
    # Set your API key
    client = OpenAI::Client.new(access_token: Rails.application.credentials["OPENAI_API_KEY"])

    # === 1. Upload the Excel File ===
    file_upload_response = client.files.upload(
      parameters: {
        file: Faraday::UploadIO.new("tmp/MIS sample.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        purpose: "assistants"
      }
    )

    file_id = file_upload_response["id"]
    Rails.logger.debug { "Uploaded file ID: #{file_id}" }

    # === 2. Create an Assistant (only once, reuse the assistant_id if already created) ===
    assistant = client.assistants.create(
      parameters: {
        name: "Excel KPI Extractor #{@entity_id} #{@portfolio_company_id} #{Time.zone.now}",
        instructions: "You are an financial analyst who can scan and review Excel files. You will be provided with an Excel file containing financial data. Your task is to extract metrics in all the worksheets in the file.",
        response_format: { type: "json_object" },
        tools: [{ type: "code_interpreter" }],
        tool_resources: {
          code_interpreter: {
            file_ids: [file_id] # See Files section above for how to upload files
          }
        },
        model: "gpt-4o"
      }
    )

    assistant_id = assistant["id"]
    Rails.logger.debug { "Assistant ID: #{assistant_id}" }

    # === 3. Create a Thread ===
    thread = client.threads.create
    thread_id = thread["id"]

    # === 4. Create a Message with the File ===
    client.messages.create(
      thread_id: thread_id,
      parameters: {
        role: "user",
        content: "Please extract the Revenue, Net Current Assets, and Number of Distributors by scanning all the worksheets in the Excel workbook. Please provide the extracted values across all dates for a specific KPI in json format for example {revenue: {date_1: 10000, date_1: 20000}}. Always return pure json. and do not add ```json or ``` at the start and end of the response."
      }
    )

    # === 5. Run the Assistant ===
    run_id = client.runs.create(
      thread_id: thread_id,
      parameters: {
        assistant_id: assistant_id,
        response_format: { type: "json_object" }
      }
    )["id"]
    Rails.logger.debug { "Run ID: #{run_id}" }

    # === 6. Poll for Completion ===
    loop do
      response = client.runs.retrieve(id: run_id, thread_id: thread_id)
      status = response['status']

      case status
      when 'queued', 'in_progress', 'cancelling'
        Rails.logger.debug "."
        sleep 3 # Wait one second and poll again
      when 'completed'
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

    # === 7. Get the Response ===
    messages = client.messages.list(thread_id: thread_id)
    response_text = messages["data"].first["content"].map { |c| c["text"]["value"] }.join("\n")

    # puts "\n==== Extracted Metrics ===="
    Rails.logger.debug response_text

    # puts messages
    response_text
  end
end
