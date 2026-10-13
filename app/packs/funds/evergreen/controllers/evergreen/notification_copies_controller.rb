# "Copy from fund…" on an evergreen fund's Notifications tab (open-ended-funds § Notifications)
module Evergreen
  class NotificationCopiesController < BaseController
    before_action :require_evergreen!

    def new
      authorize @fund, :update?
      @sources = visible_sources
    end

    def create
      authorize @fund, :update?
      from = visible_sources.find { |f| f.id == params[:from_fund_id].to_i }
      return redirect_to(new_evergreen_notification_copy_path(@fund), alert: "Choose a fund to copy from") unless from

      copied, skipped = EvergreenNotificationCopy.call(from:, to: @fund)
      redirect_to fund_path(@fund, tab: "evergreen-notifications-tab"),
                  notice: "#{copied} #{'template'.pluralize(copied)} copied from #{from.name}#{", #{skipped} skipped (already set here)" if skipped.positive?}"
    end

    private

    # Only funds this user can see (Pundit scope), not every evergreen fund of the entity
    def visible_sources
      visible = policy_scope(Fund).pluck(:id)
      EvergreenNotificationCopy.sources(@fund).select { |f| visible.include?(f.id) }
    end
  end
end
