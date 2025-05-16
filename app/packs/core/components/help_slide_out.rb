class HelpSlideOut < ViewComponent::Base
  include Turbo::FramesHelper # for turbo_frame_tag
  include Rails.application.routes.url_helpers # for tasks_path and other routes

  def initialize(class_name:, current_user:, action: "show", id: nil, css_class: "")
    super
    @class_name = class_name
    @action = action
    @id = id
    @current_user = current_user
    # Any additional css classes to be attached to the card
    @css_class = css_class
  end
end
