class ComplianceAssistant < AiAssistant
  COMPLIANCE_INSTRUCTIONS = "You're a helpful Fund compliance manager who will be required to perform compliance checks on the data provided to you. For each compliance check, think step by step and break down what data is required and use the tools provided to get the data required and perform any calculations. Do not add any ```json to the output".freeze

  def self.run_ai_checks(record, user_id, schedule)
    msg = "Running compliance checks for #{record} with schedule #{schedule} id: #{record.id}"
    send_notification(msg, user_id, :info)

    dm = AiDataManager.new(record)
    assistant = AiAssistant.new(dm, COMPLIANCE_INSTRUCTIONS)

    # Get the compliance rules for this record
    ai_rules = record.entity.ai_rules.compliance.enabled.where(for_class: record.class.name)
    ai_rules = ai_rules.for_schedule(schedule) if schedule.present?

    # The format_hint is used to tell the AI to respond with only json and no other text
    format_hint = " Respond with only json and no other text. The json should have {result: yes or no and explanation: 'The facts and numbers that explain the result'}"
    results = {}

    ai_rules.each_with_index do |ai_rule, idx|
      dm.audit_log = {}
      tries = 0
      msg = "Running compliance rule #{idx + 1}: #{ai_rule.rule} for #{ai_rule.for_class}"
      send_notification(msg, user_id, :info)
      # Sometimes the AI does function calling wrongly and that results in errors, so retry 3 times
      while tries < 3
        begin
          # Run the compliance rule
          response = assistant.query(ai_rule.rule + format_hint)
          # Strip out any ```json that the AI might have added`
          response = response[/{.*}/m]
          Rails.logger.debug response

          # Parse the response
          llm_response = JSON.parse(response)
          results[ai_rule.rule] = llm_response
          Rails.logger.debug llm_response

          # Get the parent of the record, if the record has a fund, then the parent is the fund
          parent = record.respond_to?(:fund) ? record.fund : record

          # Create a compliance check record
          AiCheck.create(entity: record.entity, parent:, owner: record, status: llm_response["result"], explanation: llm_response["explanation"], ai_rule:, rule_type: ai_rule.rule_type_label, audit_log: dm.audit_log.to_json)

          # If the rule is run successfully, then break out of the loop
          break
        rescue StandardError => e
          Rails.logger.error(e.backtrace.join("\n"))
          send_notification("Error running compliance rule #{ai_rule.name} for #{ai_rule.for_class}. Error: #{e.message}", user_id, :error)
        end
        tries += 1
      end
    end

    send_notification("#{ai_rules.count} compliance checks completed for #{record}.", user_id)

    results
  end
end
