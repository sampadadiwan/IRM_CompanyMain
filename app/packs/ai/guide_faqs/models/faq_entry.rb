# frozen_string_literal: true

# One FAQ question and answer on a user guide, managed by CapHive support in FAQ Manager
# (docs/modules/ai/customer_support_agent/guide_faq_search_prd.md). Production is the master copy.
#
# Published entries render on the guide page (FaqSectionRenderer, via WithGuideRendering)
# and are indexed in Elasticsearch for the Customer Support Agent (FaqEntryIndex,
# GuideSearch). Drafts and archived entries are visible only in FAQ Manager.
#
# @see FaqEntriesController
class FaqEntry < ApplicationRecord
  audited

  # Group key => heading shown on the guide page, in display order.
  GROUPS = {
    "navigation" => "Navigation and getting there",
    "how_to" => "Creating, updating and managing",
    "why" => "Why use it",
    "what_happens" => "What happens when I…",
    "troubleshooting" => "Troubleshooting and edge cases"
  }.freeze

  STATUSES = %w[draft published archived].freeze

  # `public` entries also render for anonymous visitors, on guides PublicGuidesController allowlists.
  AUDIENCES = %w[signed_in public].freeze

  # Re-verify an answer against the app at least this often (FaqVerificationJob).
  VERIFY_EVERY = 180.days

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :source_message, class_name: "AgentChatMessage", optional: true

  acts_as_list scope: %i[guide_key faq_group], add_new_at: :bottom

  validates :guide_key, :faq_group, :question, :answer, presence: true
  validates :faq_group, inclusion: { in: GROUPS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :question, length: { maximum: 300 }, uniqueness: { scope: :guide_key, case_sensitive: false }
  validates :answer, length: { maximum: 2000 }
  validates :keywords, length: { maximum: 500 }
  validate :guide_must_exist
  validate :public_only_on_public_guides
  validate :references_must_resolve, if: :published?

  scope :published, -> { where(status: "published") }
  scope :ordered, -> { order(:guide_key, Arel.sql(group_order_sql), :position) }

  # Publish, archive and edits of published entries reach Elasticsearch through the chewy queue.
  update_index("faq_entry") { self }

  # @return [String] SQL CASE expression ordering faq_group by GROUPS
  def self.group_order_sql
    whens = GROUPS.keys.each_with_index.map { |key, idx| "WHEN '#{key}' THEN #{idx}" }.join(" ")
    "CASE faq_group #{whens} ELSE 99 END"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[guide_key faq_group status audience question answer keywords needs_verification updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  # @return [String] the guide's title, e.g. "Capital Calls"
  def guide_title
    GuideCatalog.title(guide_key)
  end

  # @return [String] heading for this entry's group
  def group_label
    GROUPS.fetch(faq_group, faq_group.to_s.humanize)
  end

  # @return [String] in-app URL of this entry on its guide page
  def url
    "/user_guides/#{guide_key}#faq-#{id}"
  end

  # @param user [User]
  # @return [Boolean] whether the entry was published; errors are on the record when false
  def publish!(user)
    self.status = "published"
    self.published_at = Time.current
    self.last_verified_at = Time.current
    self.needs_verification = false
    self.verification_errors = nil
    self.updated_by = user
    save
  end

  # @param user [User]
  # @return [Boolean]
  def archive!(user)
    update(status: "archived", updated_by: user)
  end

  # @param user [User]
  # @return [Boolean]
  def verify!(user)
    problems = reference_errors
    return false if problems.any? && errors.add(:answer, problems.to_sentence)

    update(last_verified_at: Time.current, needs_verification: false, verification_errors: nil, updated_by: user)
  end

  # @return [Array<String>] broken paths and guide links in the answer
  def reference_errors
    GuideReferenceCheck.errors(answer, guide_key: guide_key)
  end

  # Nightly re-check (FaqVerificationJob): flags answers whose paths or links broke, or that
  # have not been verified within VERIFY_EVERY. Does not unpublish.
  #
  # @return [void]
  def refresh_verification!
    problems = reference_errors
    problems << "not verified since #{I18n.l(last_verified_at.to_date)}" if last_verified_at && last_verified_at < VERIFY_EVERY.ago
    problems << "never verified" if last_verified_at.nil?
    update_columns(needs_verification: problems.any?, verification_errors: problems.presence, updated_at: Time.current)
  end

  private

  def guide_must_exist
    return if guide_key.blank? || GuideCatalog.exists?(guide_key)

    errors.add(:guide_key, "is not a guide under docs/user_guides")
  end

  def public_only_on_public_guides
    return unless audience == "public"
    return if PublicGuidesController::PUBLIC_GUIDE_IDS.include?(guide_key)

    errors.add(:audience, "can be public only on a guide readable without a login")
  end

  def references_must_resolve
    reference_errors.each { |problem| errors.add(:answer, problem) }
  end
end
