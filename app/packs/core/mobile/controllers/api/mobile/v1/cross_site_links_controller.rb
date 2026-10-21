# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # POST /api/mobile/v1/cross_site_links { site } — the app's region switch, step 1
      # (openspec/changes/lp-mobile-multi-site, design card ②).
      #
      # The website's region switch (UsersController#cross_site_link) without the browser
      # redirect: the same checks, the same signed, five-minute, single-use CrossSiteLink, but
      # with the app's own purpose so a link minted here can only be redeemed by the other
      # region's POST /api/mobile/v1/session/cross_site — never as a website sign-in, and a
      # website link never as a phone session (MS-X2).
      class CrossSiteLinksController < BaseController
        PURPOSE = "mobile_cross_site"

        def create
          authorize current_user, :show_self?, policy_class: MobileSelfPolicy
          code = SiteRegistry.normalize(params.require(:site))

          # Nothing to sign with, an undeployed region or this same region: the website gives one
          # "region not available" answer for all three, and so does the app (MS-E3, MS-X3)
          return region_unavailable unless CrossSiteTrust.configured? && SiteRegistry.known?(code) &&
                                           code != SiteRegistry.current_code

          # The website's own rule: only regions this user belongs to (MS-X1)
          return region_unavailable unless UserPolicy.new(current_user, current_user).cross_site_link?(site: code)

          token = CrossSiteLink.new.generate(current_user.email, purpose: PURPOSE, site: code,
                                                                 from: SiteRegistry.current_code)
          render json: { token:, site: code, url: SiteRegistry.url_for(code) }, status: :created
        end

        private

        def region_unavailable
          render_error("region_unavailable", status: :unprocessable_content)
        end
      end
    end
  end
end
