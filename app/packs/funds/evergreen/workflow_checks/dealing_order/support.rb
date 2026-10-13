# Shared helpers for the evergreen order journey checks.
module WorkflowChecks
  module DealingOrder
    module Support
      private

      def order_path(order)
        Rails.application.routes.url_helpers.evergreen_order_path(order.fund_id, order.id)
      end

      def fill_for(order)
        order.dealing_fills.order(:id).last
      end
    end
  end
end
