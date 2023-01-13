class EsopLetterJob < ApplicationJob
  queue_as :doc_gen

  def perform(id)
    Chewy.strategy(:sidekiq) do
      Rails.logger.debug { "EsopLetterJob: Holding #{id} start" }
      holding = Holding.find(id)
      EsopLetterGenerator.new(holding)
      Rails.logger.debug { "EsopLetterJob: Holding #{id} end" }
    end
  end
end
