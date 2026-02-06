class RecurringTaskGeneratorJob < ApplicationJob
  queue_as :default

  def perform
    rules = TaskRecurrenceRule.where("end_date IS NULL OR end_date >= ?", Time.current.beginning_of_day)
    Rails.logger.info "[RecurringTaskGeneratorJob] Found #{rules.count} active rules. Time: #{Time.current}"
    rules.find_each do |rule|
      generate_instances_for(rule)
    end
  end

  private

  def generate_instances_for(rule)
    # Define the horizon (end of next quarter)
    horizon = 3.months.from_now.end_of_quarter
    Rails.logger.info "[RecurringTaskGeneratorJob] Processing Rule ID: #{rule.id}, Horizon: #{horizon}"

    # Initialize IceCube Schedule
    schedule = IceCube::Schedule.new(rule.start_date)

    # Parse rrule string into IceCube Rule
    # IceCube expects DTSTART in the rule if it's from_ical, or we can just pass the rule.
    # But typically from_ical works well for the rule part.
    begin
      rrule_str = rule.rrule
      rrule_str = "FREQ=#{rrule_str}" unless rrule_str.include?("FREQ=")

      # Handle Quarterly special case for IceCube
      if rrule_str.include?("FREQ=QUARTERLY")
        interval = rrule_str.match(/INTERVAL=(\d+)/)&.captures&.first || 1
        ice_cube_rule = IceCube::Rule.monthly(interval.to_i * 3)
      else
        ice_cube_rule = IceCube::Rule.from_ical(rrule_str)
      end
      ice_cube_rule.until(rule.end_date) if rule.end_date.present?
      schedule.add_recurrence_rule(ice_cube_rule)
    rescue StandardError => e
      Rails.logger.error "[RecurringTaskGeneratorJob] Error parsing rrule: #{e.message}"
      # Fallback or re-raise
      raise e
    end

    # If end_date is specified, respect it in the schedule
    # Note: schedule.end_time refers to the end of the event duration, not the recurrence end.
    # We must set UNTIL on the recurrence rule itself.

    # Get occurrences between last generation and horizon
    # IceCube occurrences_between(start, end) is exclusive of both start and end times.
    # To include the start date on first run, we subtract a second.
    # On subsequent runs, rule.generated_until will be the previous horizon.
    effective_start = rule.generated_until || (rule.start_date - 1.second)

    # We use occurrences(horizon) to get everything up to and including the horizon
    # then filter for those after effective_start
    occurrences = schedule.occurrences(horizon).select { |o| o > effective_start }
    Rails.logger.info "[RecurringTaskGeneratorJob] Found #{occurrences.count} occurrences between #{effective_start} and #{horizon}"

    occurrences.each do |occurrence_time|
      # Skip if an instance already exists for this exact time
      if Task.exists?(task_recurrence_rule_id: rule.id, original_start_date: occurrence_time)
        Rails.logger.info "[RecurringTaskGeneratorJob] Task already exists for Rule #{rule.id} at #{occurrence_time}. Skipping."
        next
      end

      Rails.logger.info "[RecurringTaskGeneratorJob] Creating task for Rule #{rule.id} at #{occurrence_time}"

      # Prepare attributes
      task_attributes = rule.task_template_payload.merge(
        "task_recurrence_rule_id" => rule.id,
        "original_start_date" => occurrence_time,
        "due_date" => occurrence_time.to_date,
        "entity_id" => rule.entity_id
      )

      # ActionText fields (details) need to be handled if they are in the payload
      Task.create!(task_attributes)
    end

    rule.update!(generated_until: horizon)
  end
end
