class ComplianceAssistant
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  def initialize(data_manager)
    @data_manager = data_manager
  end

  INSTRUCTIONS = "You're a helpful Fund compliance manager who will be required to perform compliance checks on the data provided to you. For each compliance check, think step by step and break down what data is required and use the tools provided to get the data required and perform any calculations. Do not add any ```json to the output".freeze

  def assistant
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "gpt-4o" })

    @assistant ||= Langchain::Assistant.new(
      llm: @llm,
      tools: [@data_manager, Langchain::Tool::Calculator.new],
      instructions: INSTRUCTIONS
    )

    @assistant
  end

  def query(query_string)
    assistant.add_message(content: query_string)
    assistant.run(auto_tool_execution: true)
    assistant.messages[-1].content
  end

  def self.send_notification(message, user_id, level = "success")
    Rails.logger.debug message
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end

  def self.run_compliance_checks(record, user_id)
    msg = "Running compliance checks for #{record} with id: #{record.id}"
    send_notification(msg, user_id, :info)

    dm = ComplianceDataManager.new(record)
    ai = ComplianceAssistant.new(dm)

    # Get the compliance rules for this record
    compliance_rules = record.entity.compliance_rules.where(for_class: record.class.name)

    # The format_hint is used to tell the AI to respond with only json and no other text
    format_hint = " Respond with only json and no other text. The json should have {result: yes or no and explanation: 'The explanation of the result'}"
    results = {}

    compliance_rules.each_with_index do |compliance_rule, idx|
      dm.audit_log = {}
      tries = 0
      msg = "Running compliance rule #{idx + 1}: #{compliance_rule.rule} for #{compliance_rule.for_class}"
      send_notification(msg, user_id, :info)
      # Sometimes the AI does function calling wrongly and that results in errors, so retry 3 times
      while tries < 3
        begin
          # Run the compliance rule
          llm_response = JSON.parse(ai.query(compliance_rule.rule + format_hint))
          results[compliance_rule.rule] = llm_response
          Rails.logger.debug llm_response

          # Get the parent of the record, if the record has a fund, then the parent is the fund
          parent = record.respond_to?(:fund) ? record.fund : record

          # Create a compliance check record
          ComplianceCheck.create(entity: record.entity, parent:, owner: record, status: llm_response["result"], explanation: llm_response["explanation"], compliance_rule:, audit_log: dm.audit_log.to_json)

          # If the rule is run successfully, then break out of the loop
          break
        rescue StandardError => e
          Rails.logger.error(e)
        end
        tries += 1
      end
    end

    send_notification("#{compliance_rules.count} compliance checks completed for #{record}.", user_id)

    results
  end
end
