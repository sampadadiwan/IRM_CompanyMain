class AiFundChecksJob < ApplicationJob
  queue_as :ai_checks

  def perform(parent_type, parent_id, user_id, for_classes, rule_type, schedule)
    # Find the model
    parent = parent_type.constantize.find(parent_id)

    send_notification("Starting #{rule_type} for #{for_classes}, #{schedule} checks..", user_id, :info)
    for_classes.each do |for_class|
      if for_class == parent.class.to_s
        Rails.logger.debug { "Running checks for #{parent}, rule_type: #{rule_type}, schedule: #{schedule}" }
        AiChecksJob.perform_later(for_class, parent.id, user_id, rule_type, schedule)
      else
        parent.send(for_class.underscore.pluralize).each do |model|
          Rails.logger.debug { "Running checks for #{model}, rule_type: #{rule_type}, schedule: #{schedule}" }
          AiChecksJob.perform_later(for_class, model.id, user_id, rule_type, schedule)
        end
      end
    end

    send_notification("Checks completed for #{parent}.", user_id)
  end
end
