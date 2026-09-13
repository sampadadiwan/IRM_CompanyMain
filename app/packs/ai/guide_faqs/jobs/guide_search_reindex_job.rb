# frozen_string_literal: true

# Rebuilds FaqEntryIndex so changed synonym rules take effect. Chewy's reset! builds a new index
# and swaps the alias, so searches keep working during the rebuild.
class GuideSearchReindexJob < ApplicationJob
  queue_as :chewy

  def perform
    return if Rails.env.test?

    FaqEntryIndex.reset!
  rescue StandardError => e
    Rails.logger.error("[GuideSearchReindexJob] #{e.class}: #{e.message}")
  end
end
