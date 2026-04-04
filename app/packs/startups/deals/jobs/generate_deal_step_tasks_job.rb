# This job handles the automatic generation of tasks for a DealInvestor
# based on the tasks_csv field of the current DealActivity (step).
class GenerateDealStepTasksJob < ApplicationJob
  queue_as :default

  # @param deal_investor_id [Integer] ID of the DealInvestor
  # @param user_id [Integer] ID of the user who moved the step (to assign tasks)
  # @param deal_activity_id [Integer] Optional ID of the specific activity to generate tasks for
  def perform(deal_investor_id, user_id = nil, deal_activity_id = nil)
    deal_investor = DealInvestor.find(deal_investor_id)
    # Use provided activity or fallback to the current activity the investor is on
    target_activity = if deal_activity_id.present?
                        DealActivity.find(deal_activity_id)
                      else
                        deal_investor.deal_activity
                      end

    # If there is no activity or no tasks defined, we return
    return if target_activity.blank? || target_activity.tasks_csv.blank?

    # We split the CSV by both commas and newlines to be flexible
    # and remove any blank segments or surrounding whitespace
    task_titles = target_activity.tasks_csv.split(/[,\n]/).map(&:strip).reject(&:blank?).uniq

    # We iterate through each task title and create a Task record if it doesn't already exist
    task_titles.each do |title|
      # Deduplication: Check if a task with the same title already exists for this DealInvestor
      # This prevents duplicate tasks if a deal is moved back and forth through steps.
      existing_task = Task.find_by(
        owner: deal_investor,
        details: title
      )

      next if existing_task.present?

      # Find a fallback user if user_id is nil
      effective_user_id = user_id || deal_investor.entity.employees.first&.id

      # Create the Task
      Task.create!(
        entity_id: deal_investor.entity_id,
        user_id: effective_user_id,          # Link to an effective user
        assigned_to_id: user_id,             # Assign to the person who moved the step
        owner: deal_investor,
        details: title,
        due_date: Time.zone.today + 7.days,  # Default due date of 1 week
        category: "Other"                    # Default category for deal tasks
      )
    end
  end
end
