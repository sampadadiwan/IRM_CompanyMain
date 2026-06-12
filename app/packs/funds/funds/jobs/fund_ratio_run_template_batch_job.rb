# Runs a list of FundRatioRunTemplate records sequentially within a single background job.
# Called by trigger_all and trigger_by_tag so templates execute one after another
# instead of being enqueued as independent concurrent Sidekiq jobs.
#
# Template IDs are pre-validated by the controller (blockers skipped) and passed
# in ordered sequence. The job re-fetches each template and calls
# FundRatiosScenarioJob synchronously (perform_now) so the next template only
# starts after the previous one finishes.
#
# Individual per-run success notifications are suppressed; one consolidated alert
# is sent at the end with links to all completed runs.
class FundRatioRunTemplateBatchJob < ApplicationJob
  include Rails.application.routes.url_helpers
  include ApplicationHelper

  queue_as :low
  sidekiq_options retry: 1

  def perform(template_ids, end_date, user_id)
    # Re-fetch in the caller-supplied order so position-based sequencing is respected.
    templates_by_id = FundRatioRunTemplate.where(id: template_ids).index_by(&:id)

    completed_runs = []

    template_ids.each do |id|
      template = templates_by_id[id]
      next unless template # guard: template deleted between enqueue and execution

      # perform_now runs the job inline — next template waits until this one completes.
      # suppress_notification: true prevents per-run alerts; we send one batch alert below.
      run = FundRatiosScenarioJob.new.perform(
        template.anchor_fund_id,
        end_date,
        user_id,
        fund_ids: template.fund_ids.presence,
        portfolio_company_ids: template.portfolio_company_ids.presence,
        portfolio_companies_tags: template.portfolio_companies_tags.presence,
        portfolio_companies_sectors: template.sectors.presence,
        currency: template.currency.presence,
        type: template.run_type,
        suppress_notification: true,
        template_id: template.id
      )
      completed_runs << run if run
    end

    notify_batch_complete(completed_runs, user_id)
  end

  private

  def notify_batch_complete(runs, user_id)
    return if runs.empty?

    h           = ActionController::Base.helpers
    badge_class = 'mb-1 badge bg-primary-subtle text-primary'

    # Link each run to its show page so the user can inspect it directly.
    run_links = runs.map do |run|
      h.link_to(run.to_s, fund_ratio_run_path(run), class: badge_class, target: '_blank', rel: 'noopener')
    end.join(' ')

    index_link = h.link_to('View All Runs', fund_ratio_runs_path, class: badge_class, target: '_blank', rel: 'noopener')

    message = "#{runs.size} ratio #{'run'.pluralize(runs.size)} completed.<br>#{run_links} #{index_link}"
    UserAlert.new(user_id:, message:, level: 'success').broadcast
  end
end
