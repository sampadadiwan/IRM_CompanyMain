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
end
