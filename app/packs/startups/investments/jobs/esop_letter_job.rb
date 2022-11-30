class EsopLetterJob < ApplicationJob
  queue_as :default

  def perform(id)
    Chewy.strategy(:atomic) do
      Rails.logger.debug { "EsopLetterJob: Holding #{id} start" }
      holding = Holding.find(id)
      EsopLetterGenerator.new(holding)
      Rails.logger.debug { "EsopLetterJob: Holding #{id} end" }
    end
  end
end
