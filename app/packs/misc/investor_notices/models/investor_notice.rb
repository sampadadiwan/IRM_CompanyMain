class InvestorNotice < ApplicationRecord
  belongs_to :entity
  # owner is optional: nil means an entity-wide notice (targets every investor
  # of `entity`); a present owner (Fund/SecondarySale/Deal) scopes the notice
  # to only the investors granted AccessRight visibility into that owner — see
  # #investors below, which both InvestorNoticeJob and the entry admin form
  # (investor_notice_entries/_form.html.erb) rely on for the audience.
  belongs_to :owner, optional: true, polymorphic: true
  has_many :investor_notice_entries, dependent: :destroy
  has_many :investor_notice_items, dependent: :destroy
  accepts_nested_attributes_for :investor_notice_items, reject_if: :all_blank, allow_destroy: true

  has_rich_text :details

  validates :title, :start_date, :end_date, presence: true
  # A notice saved without an owner may be given one later, but only one of its own firm (C)
  validate { validate_parent_in_own_firm(:owner) }
  validates :btn_label, length: { maximum: 40 }
  validates :category, length: { maximum: 30 }
  # Dry-run the expression at save time so a typo shows up to the GP admin
  # immediately, instead of silently hiding the notice from everyone later —
  # see InvestorNoticeCriteriaEvaluator.validate.
  validate :criteria_expression_is_valid, if: -> { criteria.present? }

  # Only bust investor caches when something the carousel actually renders
  # changed, not on every no-op save (see #update_investors).
  after_commit :update_investors, unless: :destroyed?, if: :saved_changes?
  after_commit :generate_investor_notice_entries, if: proc { |notice| notice.generate && notice.saved_change_to_generate? && !notice.destroyed? }

  def generate_investor_notice_entries
    InvestorNoticeJob.perform_later(id)
  end

  def update_investors
    # Bust the cache for this notice for all investor_entity_ids, see carousel is cached based on that.
    # distinct+pluck (not collect) so this stays a single SQL query even when a
    # notice has many entries.
    investor_entity_ids = investor_notice_entries.distinct.pluck(:investor_entity_id)
    Entity.where(id: investor_entity_ids).update_all(updated_at: Time.zone.now)
  end

  # The investors this notice is meant for. Owner-scoped notices (Fund/
  # SecondarySale/Deal) use that owner's AccessRight-granted investors,
  # honoring access_rights_metadata as an extra filter (e.g. "Buyer" vs
  # "Seller" for a SecondarySale); entity-wide notices (owner nil) target
  # every investor of the authoring GP entity. Guard with respond_to? rather
  # than assuming every owner type exposes a plain `investors` method — e.g.
  # SecondarySale only exposes buyer_investors/seller_investors, both backed
  # by investors_granted_access.
  def investors
    if owner.respond_to?(:investors_granted_access)
      owner.investors_granted_access(access_rights_metadata)
    else
      entity.investors
    end
  end

  # What a given logged-in user actually sees in their dashboard carousel.
  # This is a display-time filter only — it decides which of the notice's
  # already-generated InvestorNoticeEntry rows this particular user gets
  # shown; it has no say in *whose* entries exist in the first place. That
  # audience decision (owner-scoped Fund/SecondarySale/Deal vs. entity-wide)
  # is made earlier and separately, by InvestorNoticeJob#create_notice_entries
  # (see InvestorNotice#investors) — this method just reads the results.
  def self.notices(user, gp_entity_id: nil)
    # Gate 1: only currently-active notices, joined to their entries (who the
    # notice is for) and, via the authoring GP entity, that GP's
    # investor_accesses (who is allowed to see that GP's stuff at all).
    notices = InvestorNotice.joins(:investor_notice_entries, entity: :investor_accesses).where("investor_notices.active=?", true)

    # Gate 2: the actual "is this notice for me" check. `user.entity_id` is
    # the LP's own firm (an investor *user* belongs to an investor_entity —
    # it isn't the same row as the `Investor` record itself), so this
    # requires an InvestorNoticeEntry whose investor_entity_id matches that
    # firm, and which is itself still active (an entry can be deactivated
    # independently of the parent notice, e.g. if that investor is removed).
    notices = notices.where("investor_notice_entries.investor_entity_id=? and investor_notice_entries.active=?", user.entity_id, true)

    # Gate 3: independent of being targeted by an entry, this user must also
    # hold an *approved* InvestorAccess to the GP that authored the notice —
    # being in the audience isn't enough if this LP's access to that GP was
    # never approved, or was later revoked.
    notices = notices.where("investor_accesses.user_id=? and investor_accesses.approved=?", user.id, true)

    # Gate 4: CapHive-staff-as-investor preview path only — restricts to the
    # platform's own entity so staff can't preview an arbitrary GP's notices
    # by spoofing an investor_entity_id. Not part of the normal LP path.
    notices = notices.where("investor_accesses.entity_id=?", ENV.fetch("CAPHIVE_ENTITY_ID", nil)) if user.curr_role == "employee"

    # Gate 5: When the LP has picked a GP in the dashboard GP switcher, only
    # surface notices published by that GP entity (investor_notices.entity_id
    # is the GP that created the notice) — an LP can have approved access to
    # more than one GP.
    notices = notices.where("investor_notices.entity_id=?", gp_entity_id) if gp_entity_id.present?

    # Gate 6: don't rely solely on the daily InvestorNoticeJob run to flip
    # `active` — a notice future-dated via start_date, or one whose end_date
    # passed since this morning's run, must not appear in the meantime.
    today = Time.zone.today
    notices = notices.where("investor_notices.start_date <= ? and investor_notices.end_date >= ?", today, today)

    notices
  end

  private

  def criteria_expression_is_valid
    result = InvestorNoticeCriteriaEvaluator.validate(criteria, self)
    errors.add(:criteria, "is invalid: #{result}") unless result == true
  end
end
