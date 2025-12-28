class ApplicationController < ActionController::Base
  layout 'modernize'
  include Pagy::Backend
  include Pundit::Authorization

  include WithAuthentication
  include WithFilterParams
  include WithBulkActions
  include WithEmailPreview
  include WithLocale
  include WithSetupCustomFields

  before_action :prepare_exception_notifier

  private

  def rss_kb
    # RSS in KB for current process
    `ps -o rss= -p #{Process.pid}`.to_i
  end

  def log_memory_delta
    before = rss_kb
    yield
  ensure
    after = rss_kb
    delta_mb = (after - before) / 1024.0
    Rails.logger.info("[mem] #{request.request_method} #{request.fullpath} pid=#{Process.pid} ΔRSS=#{delta_mb.round(1)}MB (#{before / 1024}→#{after / 1024}MB)")
  end
end
