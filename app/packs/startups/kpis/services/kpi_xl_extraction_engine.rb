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
    client = initialize_client
    file_id = upload_excel_file(client)
    assistant_id = create_assistant(client, file_id)
    thread_id = create_thread(client)
    send_message(client, thread_id)
    run_id = run_assistant(client, assistant_id, thread_id)
    poll_for_completion(client, run_id, thread_id)
    extract_response(client, thread_id)
  end

  private

  def initialize_client
    OpenAI::Client.new(access_token: Rails.application.credentials["OPENAI_API_KEY"])
  end

  def upload_excel_file(client)
    response = client.files.upload(
      parameters: {
        file: Faraday::UploadIO.new("tmp/MIS sample.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        purpose: "assistants"
      }
    )
    file_id = response["id"]
    Rails.logger.debug { "Uploaded file ID: #{file_id}" }
    file_id
  end

  def create_assistant(client, file_id)
    assistant = client.assistants.create(
      parameters: {
        name: "Excel KPI Extractor #{@entity_id} #{@portfolio_company_id} #{Time.zone.now}",
        instructions: "You are a financial analyst who can scan and review Excel files. You will be provided with an Excel file containing financial data. Your task is to extract metrics in all the worksheets in the file.",
        response_format: { type: "json_object" },
        tools: [{ type: "code_interpreter" }],
        tool_resources: {
          code_interpreter: {
            file_ids: [file_id]
          }
        },
        model: "gpt-4o"
      }
    )
    assistant_id = assistant["id"]
    Rails.logger.debug { "Assistant ID: #{assistant_id}" }
    assistant_id
  end

  def create_thread(client)
    thread = client.threads.create
    thread["id"]
  end

  def send_message(client, thread_id)
    client.messages.create(
      thread_id: thread_id,
      parameters: {
        role: "user",
        content: "Please extract the Revenue, Net Current Assets, and Number of Distributors by scanning all the worksheets in the Excel workbook. Please provide the extracted values across all dates for a specific KPI in json format for example {revenue: {date_1: 10000, date_1: 20000}}. Always return pure json. and do not add ```json or ``` at the start and end of the response."
      }
    )
  end

  def run_assistant(client, assistant_id, thread_id)
    run_id = client.runs.create(
      thread_id: thread_id,
      parameters: {
        assistant_id: assistant_id,
        response_format: { type: "json_object" }
      }
    )["id"]
    Rails.logger.debug { "Run ID: #{run_id}" }
    run_id
  end

  def poll_for_completion(client, run_id, thread_id)
    loop do
      response = client.runs.retrieve(id: run_id, thread_id: thread_id)
      status = response['status']

      case status
      when 'queued', 'in_progress', 'cancelling'
        Rails.logger.debug "."
        sleep 3
      when 'completed'
        break
      when 'requires_action'
        Rails.logger.debug { "Action required: #{response['last_error']}" }
        break
      when 'cancelled', 'failed', 'expired'
        Rails.logger.debug response['last_error'].inspect
        break
      else
        Rails.logger.debug { "Unknown status response: #{status}" }
      end
    end
  end

  def extract_response(client, thread_id)
    messages = client.messages.list(thread_id: thread_id)
    response_text = messages["data"].first["content"].map { |c| c["text"]["value"] }.join("\n")
    Rails.logger.debug response_text
    response_text
  end
end
