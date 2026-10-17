# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # POST /api/mobile/v1/web_handoffs { path } — a one-time link that opens a website page in
      # the app's in-app browser, already signed in (design card ⑦; H13, E23, X16).
      #
      # Reuses the cross-region login credential (CrossSiteLink: signed, 5-minute, single-use)
      # with its own purpose, so a link minted here can never be redeemed as a region switch and
      # vice versa. The access token itself never goes into a URL.
      class WebHandoffsController < BaseController
        PURPOSE = "mobile_web"
        MAX_PATH_LENGTH = 500

        def create
          authorize current_user, :show_self?, policy_class: MobileSelfPolicy
          path = params.require(:path).to_s
          # E23 — same-site paths only
          return render_error("invalid_path", status: :unprocessable_content) unless self.class.safe_path?(path)

          # The hand-off credential is signed with the cross-region secret; without it there is no
          # safe way to open the website signed in, so say so rather than fail with a 500
          return render_error("handoff_unavailable", status: :service_unavailable) unless CrossSiteTrust.configured?

          token = CrossSiteLink.new.generate(current_user.email, purpose: PURPOSE, site: SiteRegistry.current_code,
                                                                 from: SiteRegistry.current_code)
          render json: { url: users_mobile_handoff_url(token:, path:) }, status: :created
        end

        # A relative path to a route this app actually serves — never another host
        # ("//evil.com", "https://evil.com", "/\\evil.com" are all refused).
        def self.safe_path?(path)
          return false if path.blank? || path.length > MAX_PATH_LENGTH
          return false unless path.start_with?("/") && !path.start_with?("//") && path.exclude?("\\")

          uri = URI.parse(path)
          return false if uri.host || uri.scheme

          Rails.application.routes.recognize_path(uri.path, method: :get)
          true
        rescue URI::InvalidURIError, ActionController::RoutingError
          false
        end
      end
    end
  end
end
