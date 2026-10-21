# The fund managers (GP entities) an LP can pick between in the mobile app, and which one a
# request is for (openspec/changes/lp-mobile-multi-site, design card ③).
#
# The list is the website's LP dashboard dropdown (entities/_vc_dashboard): the entities of the
# user's APPROVED investor accesses, sorted by name. The app always shows exactly one of them —
# never every GP mixed together — so a request without a usable choice falls back to the first,
# the same default the website uses on a first load.
class MobileFundManagers
  def initialize(user)
    @user = user
  end

  # How long the logo link /me hands out stays valid — the website sidebar's own expiry
  LOGO_URL_EXPIRY = 7.days

  # [{ id:, name:, logo_url: }] sorted by name, case-insensitively (as the website sorts them).
  # logo_url is the fund manager's uploaded logo (the app's branding when it is picked), nil
  # when there is none — the app then shows the CapHive mark.
  def list
    @list ||= Entity.where(id: InvestorAccess.where(user_id: user.id, approved: true).select(:entity_id))
                    .select(:id, :name, :logo_data)
                    .sort_by { |entity| entity.name.to_s.downcase }
                    .map { |entity| { id: entity.id, name: entity.name, logo_url: logo_url(entity) } }
  end

  # The fund manager a request is for: the requested one when the user still has access to it
  # (MF-H2), otherwise the first in the list (MF-H1, MF-E1). nil only when the user has none
  # (MF-E2), and then every list the app shows is empty.
  def resolve(requested_id)
    ids = list.pluck(:id)
    ids.include?(requested_id.to_i) ? requested_id.to_i : ids.first
  end

  private

  attr_reader :user

  # A signed link to the logo, or nil without one (or when storage cannot sign it — branding
  # must never break /me)
  def logo_url(entity)
    entity.logo&.url(expires_in: LOGO_URL_EXPIRY.to_i)
  rescue StandardError => e
    Rails.logger.warn("[mobile_fund_managers] logo for entity #{entity.id}: #{e.class}: #{e.message}")
    nil
  end
end
