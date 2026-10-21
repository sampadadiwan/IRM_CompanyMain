# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # GET /api/mobile/v1/sites — the regions of THIS environment (openspec/changes/
      # lp-mobile-multi-site, design card ①).
      #
      # One app build serves every environment: the app knows only one address per environment
      # (production, staging, or a typed-in custom one) and asks it which regions exist. The answer
      # is this deployment's own SITES, the list the website's region switcher uses, so the app and
      # the website can never disagree on what regions an environment has, and staging never lists
      # a production site (MS-H1, MS-E1).
      #
      # Public: it runs before sign-in and reveals nothing the website's sign-in page does not.
      class SitesController < BaseController
        skip_before_action :authenticate_mobile_device!
        skip_after_action :verify_authorized

        def index
          render json: { current: SiteRegistry.current_code, sites: self.class.sites_json(SiteRegistry.codes) }
        end

        # [{ code:, label:, url: }] for the given region codes — shared with /me's switchable regions
        def self.sites_json(codes)
          codes.map do |code|
            { code:, label: I18n.t("cross_region.regions.#{code}", default: code), url: SiteRegistry.url_for(code) }
          end
        end
      end
    end
  end
end
