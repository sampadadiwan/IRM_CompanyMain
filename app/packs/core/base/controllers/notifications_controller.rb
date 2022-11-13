class NotificationsController < ApplicationController
  after_action :verify_policy_scoped, except: :index

  def index
    @activities = PublicActivity::Activity.where(entity_id: current_user.entity_id)
                                          .order("id desc").page params[:page]
  end
end
