# This job handles the automatic generation of tasks for a DealInvestor
# based on the tasks_csv field of the current DealActivity (step).
class GenerateDealStepTasksJob < ApplicationJob
  queue_as :default

  # @param deal_investor_id [Integer] ID of the DealInvestor
  # @param user_id [Integer] ID of the user who moved the step (to assign tasks)
  # @param deal_activity_id [Integer] Optional ID of the specific activity to generate tasks for
  def perform(deal_investor_id, user_id = nil, deal_activity_id = nil)
    # Use Chewy's sidekiq strategy to ensure that the job is processed in the background
    Chewy.strategy(:sidekiq) do
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
      task_titles = target_activity.tasks_csv.split(/[,\n]/).map(&:strip).compact_blank.uniq

      # Deduplication: skip the titles that this DealInvestor already has a task for, so moving a deal
      # back and forth through steps doesn't pile up copies. Task#details is an ActionText
      # attribute, so the title lives in action_text_rich_texts and the tasks.details column
      # stays NULL — the comparison has to be against the rich text body, not the column.
      existing_titles = deal_investor.tasks.includes(:rich_text_details)
                                     .filter_map { |task| task.rich_text_details&.body&.to_plain_text&.strip }
                                     .to_set

      new_titles = task_titles.reject { |title| existing_titles.include?(title) }
      return if new_titles.empty?

      # Find a fallback user if user_id is nil
      effective_user_id = user_id || deal_investor.entity.employees.first&.id

      new_titles.each do |title|
        # Create the Task
        Task.create!(
          entity_id: deal_investor.entity_id,
          user_id: effective_user_id,          # Link to an effective user
          assigned_to_id: effective_user_id,   # Assign to the person who moved the step
          owner: deal_investor,
          details: title,
          due_date: Time.zone.today + 7.days,  # Default due date of 1 week
          category: "Other"                    # Default category for deal tasks
        )
      end
    end
  end
end
