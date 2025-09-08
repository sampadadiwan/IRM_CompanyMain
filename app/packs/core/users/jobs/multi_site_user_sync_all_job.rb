class MultiSiteUserSyncAllJob < ApplicationJob
  queue_as :low

  def perform
    MultiSiteUserSyncOrchestrator.sync_all
  end
end
