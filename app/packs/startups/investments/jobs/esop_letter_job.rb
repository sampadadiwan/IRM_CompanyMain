class EsopLetterJob < ApplicationJob
  queue_as :doc_gen
  retry_on StandardError, attempts: 1

  def perform(id)
    Chewy.strategy(:active_job) do
      Rails.logger.debug { "EsopLetterJob: Holding #{id} start" }
      holding = Holding.find(id)
      EsopLetterGenerator.new(holding) if holding.option_pool.grant_letter.present?
      Rails.logger.debug { "EsopLetterJob: Holding #{id} end" }
    end
  end
end
