# Runs a list of FundRatioRunTemplate records sequentially within a single background job.
# Called by trigger_all and trigger_by_tag so templates execute one after another
# instead of being enqueued as independent concurrent Sidekiq jobs.
#
# Template IDs are pre-validated by the controller (blockers skipped) and passed
# in ordered sequence. The job re-fetches each template and calls
# FundRatiosScenarioJob synchronously (perform_now) so the next template only
# starts after the previous one finishes.
class FundRatioRunTemplateBatchJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1

  def perform(template_ids, end_date, user_id)
    # Re-fetch in the caller-supplied order so position-based sequencing is respected.
    templates_by_id = FundRatioRunTemplate.where(id: template_ids).index_by(&:id)

    template_ids.each do |id|
      template = templates_by_id[id]
      next unless template # guard: template deleted between enqueue and execution

      # perform_now runs the job inline — next template waits until this one completes.
      FundRatiosScenarioJob.new.perform(
        template.anchor_fund_id,
        end_date,
        user_id,
        fund_ids:                    template.fund_ids.presence,
        portfolio_company_ids:       template.portfolio_company_ids.presence,
        portfolio_companies_tags:    template.portfolio_companies_tags.presence,
        portfolio_companies_sectors: template.sectors.presence,
        currency:                    template.currency.presence,
        type:                        template.run_type
      )
    end
  end
end
