class AccessRight < ApplicationRecord
  include Trackable.new

  # Generates/revokes DealIngestAddress when deal access changes (FR-5).

  # To allow tag_list for creating new access rights
  attr_accessor :tag_list

  update_index('access_right') { self if index_record? }

  ALL = "All".freeze
  SELF = "Self".freeze
  SUMMARY = "Summary".freeze
  VIEWS = [ALL, SELF].freeze
  TYPES = ["All Users for Specific Stakeholder", "All Stakeholders of Specific Category", "All Stakeholders with Tag"].freeze

  # Additional permissions for access rights, for employees/advisors specifically
  flag :permissions, %i[create read update destroy]

  belongs_to :owner, polymorphic: true # , strict_loading: true
  belongs_to :entity
  # If this is a user access
  belongs_to :user, optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  # If this is a specific investor access
  belongs_to :investor, foreign_key: :access_to_investor_id, optional: true # , strict_loading: true
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :owner, prefix: :owner

  scope :investments, -> { where(access_type: "Investment") }
  scope :documents, -> { where(access_type: "Document") }
  scope :deals, -> { where(access_type: "Deal") }

  scope :for_user, ->(user_id) { where(user_id:) }
  scope :not_user, -> { where(user_id: nil) }

  scope :for, ->(owner) { where(owner_id: owner.id, owner_type: owner.class.name) }
  scope :for_access_type, ->(type) { where("access_rights.access_type=?", type) }

  scope :for_investor, lambda { |investor|
                         where("(access_rights.entity_id=?
                                        and access_rights.access_to_investor_id is NULL
                                        and access_rights.access_to_category=?)
                                        OR (access_rights.access_to_investor_id=?)",
                               investor.entity_id, investor.category, investor.id)
                       }

  scope :investor_access, lambda { |investor, user|
                            where(" (access_rights.entity_id=?) AND
                                    ( access_rights.access_to_investor_id=? OR
                                    access_rights.access_to_category=? OR
                                    access_rights.user_id=? )",
                                  investor.entity_id, investor.id, investor.category, user.id)
                          }

  scope :access_filter, lambda { |user|
    if user.investor_advisor?
      # Since he is currently playing the role of IA, we should only use the access_rights
      # given to his specific user id
      where("access_rights.user_id=? OR access_rights.access_to_investor_id=investors.id", user.id)
    elsif user.has_cached_role?(:investor_advisor) && !user.investor_advisor?
      # This is to avoid duplicates in the results of the final query
      # If the user has the role but is not currently switched as an IA for another investor
      # Then essentially he is looking for his own funds/commitments/etc - so we dont use the user_id here
      # We join only based on his own investor id
      where("investors.category=access_rights.access_to_category OR access_rights.access_to_investor_id=investors.id")
    else
      # For regular users
      where("investors.category=access_rights.access_to_category OR access_rights.access_to_investor_id=investors.id OR access_rights.user_id=?", user.id)
    end
  }

  scope :access_filter_for_rm, lambda { |user|
    where("access_rights.access_to_category='RM' OR access_rights.access_to_investor_id=rm_mappings.rm_id OR access_rights.user_id=?", user.id)
  }

  # The access filter for an investor-side list. An advisor switched into a client sees only what
  # was granted to them personally for that client - the rule Fund.for_investor and every
  # ForInvestor scope already use. access_filter also matched grants made to the client investor,
  # so approvals, secondary sales and their children were listed for the client's advisors while
  # their pages (personal grant) denied them.
  # Worked example B3-3 — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
  scope :investor_list_filter, lambda { |user|
    user.investor_advisor? ? investor_granted_access_filter(user) : access_filter(user)
  }

  # This scope is used to filter access rights for investor advisors, who manage folios for investors.
  # Investors grant access_rights to the Fund or Sale or Deal, to the investor advisor.
  # Do not call this with a user who is not an investor_advisor
  scope :investor_granted_access_filter, lambda { |user, across_all_entities: false|
    if across_all_entities && user.has_cached_role?(:investor_advisor)
      # This is used only in the case of sending emails, when the advisor is logged in as an investor, but emails need to be sent out irrespective of which investor they are currently switched into
      where("access_rights.user_id=?", user.id)
    else
      # This kicks in when the investor advisor is logged in and switches to a specific investor
      where("access_rights.user_id=? and access_rights.entity_id=?", user.id, user.entity_id)
    end
  }

  validates :access_to_email, length: { maximum: 30 }
  validates :access_type, length: { maximum: 25 }
  validates :access_to_category, length: { maximum: 20 }
  validate :any_present?

  def any_present?
    errors.add :base, "Must specify Investor or Category" if %w[access_to_investor_id access_to_category user_id].all? { |attr| self[attr].blank? }
  end

  validate :access_is_unique
  def access_is_unique
    errors.add(:owner, 'Duplicate! already has this permission') if AccessRight.where.not(id:).exists?(owner:, access_to_investor_id:, access_to_category:, user_id:, entity_id:)
  end

  def to_s
    access_to_label
  end

  def types
    case owner_type
    when "Deal"
      ["All Users for Specific Stakeholder"] + %w[Employee Advisor]
    when "Fund", "InvestmentOpportunity", "SecondarySale"
      AccessRight::TYPES + %w[Employee Advisor]
    when "Document", "Folder"
      AccessRight::TYPES + ["Specific User", "Employee"]
    else
      AccessRight::TYPES
    end
  end

  def access_to_label
    label = access_to_category if access_to_category.present?
    label ||= investor.investor_name if access_to_investor_id.present?
    label ||= user.full_name if user_id.present?

    label
  end

  # Emails of all approved investor users
  def investor_emails
    emails = []

    if access_to_investor_id.present?
      # Get all the investor -> investor access that are approved, and get the email addresses
      emails = investor.investor_accesses.approved.collect(&:email)
    elsif access_to_category.present?
      # Get all the investors with this category -> investor access that are approved, and get the email addresses
      Investor.where(entity_id:, category: access_to_category).find_each do |investor|
        emails += investor.investor_accesses.approved.collect(&:email)
      end
    end

    emails
  end

  before_save :strip_fields
  def strip_fields
    self.access_to_category = access_to_category.strip if access_to_category
    self.metadata = metadata.strip if metadata
    self.access_type = access_type.strip if access_type
    self.access_type ||= owner_type
  end

  # Replicates the current access right to a new owner (e.g., a child folder or document).
  # This is used for inheriting permissions down the hierarchy.
  # @param new_owner [ApplicationRecord] The model instance to which the access right is being copied.
  # @param validate [Boolean] Whether to run validations on the new access right.
  # @return [AccessRight] The newly created access right.
  def replicate_to(new_owner, validate: true)
    new_ar = dup
    new_ar.owner = new_owner
    # Inherit access type from the owner's class name if not explicitly set
    new_ar.access_type = new_owner.class.name
    # Don't send notifications for replicated access rights to avoid spamming users
    new_ar.notify = false
    # Don't let replicated copies re-trigger cascading: Folder#access_rights_changed enqueues a
    # FolderAccessJob for any saved access_right with cascade=true, and FolderAccessJob already
    # walks the whole descendant subtree in one pass. Leaving cascade=true here made every
    # replicated folder copy spawn its own redundant job for a subtree the caller already covered.
    new_ar.cascade = false
    # Maintain link to the original access right for cascading deletions/updates
    new_ar.parent_access_right_id = parent_access_right_id || id
    new_ar.save(validate: validate)
    new_ar
  end

  after_create_commit :send_notification
  def send_notification
    if notify && (%w[Document Folder].exclude?(owner_type) || (owner.respond_to?(:send_email) && owner.send_email))
      users.each do |user|
        msg = "You have been granted access to #{owner_type} #{owner.name} by #{entity.name}"
        AccessRightNotifier.with(record: self, entity_id:, msg:).deliver_later(user)
      end
    else
      Rails.logger.info "AccessRightNotifier: Notification skipped for AccessRight #{id} (notify: #{notify}, owner_type: #{owner_type})"
    end
  end

  # add_to_user_access_rights_cache / remove_from_user_access_rights_cache callbacks removed:
  # Policies now query access_rights directly; no serialized cache to maintain on users.
  def users
    if user_id.present?
      [user]
    elsif access_to_investor_id.present?
      investor.notification_users(owner)
    elsif access_to_category.present?
      User.joins(investor_accesses: :investor).where(entity_id:, 'investors.category': access_to_category).where(investor_accesses: { approved: true })
    else
      []
    end
  end

  # The same recipients as #users, but each paired with the investor whose access THIS right
  # grants - so a notifier can look up that investor's cc addresses (InvestorAccess#cc and
  # CapitalCommitment#cc) instead of having to guess which stakeholder an email is "for".
  #
  # Returns [user, investor] pairs. `investor` is nil when the right names a person directly
  # (#user_id, typically an employee): there is no stakeholder context to draw a cc from.
  #
  # The recipient set is deliberately derived from #users in every branch, so this cannot
  # widen or narrow who gets emailed - it only attaches the investor. See
  # docs/modules/notifications/document_notification_cc_resolution.md.
  def notification_recipients(model = owner)
    if user_id.present?
      # Guarded for the same reason as Investor#notification_users: a right naming a user whose
      # row is gone must not put a nil recipient into the fan-out.
      user ? [[user, nil]] : []
    elsif access_to_investor_id.present?
      # investor.notification_users applies the Pundit filter against `model`, exactly as
      # #users does - passing `model` through keeps a document-level right judged against the
      # document and a fund-level right against the fund.
      investor.notification_users(model).map { |contact| [contact, investor] }
    elsif access_to_category.present?
      # No policy filter here, so `model` is not needed - see category_recipients.
      category_recipients
    else
      []
    end
  end

  # Changed: Module 10 — auto-tag NDA signatory when folder AccessRight is granted.
  # Why: When a GP grants folder access to an investor AFTER the NDA is already configured,
  #   the investor's existing approved users have zero signatories. This callback checks if
  #   the folder has an enabled NDA and auto-tags the oldest approved user as signatory.
  #   Complements the InvestorAccess callback which covers the other path (access created after NDA).
  after_commit :auto_tag_nda_signatory_for_folder, on: %i[create update], if: :folder_with_investor?

  after_commit :update_owner
  # This is to bust any cached dashboards showing the commitments
  def update_owner
    # Update the investors entity to bust any cache
    Entity.where(id: investors.pluck(:investor_entity_id)).update_all(updated_at: Time.zone.now)
    # Update the owner to bust any cache
    # owner.touch
    # Tell the owner that the access rights have changed
    owner.access_rights_changed(self) if owner.respond_to?(:access_rights_changed)
  end
  # rubocop:enable Rails/SkipsModelValidations

  after_destroy_commit lambda {
    AccessRightsDeletedJob.perform_later(owner_id, owner_type, id) if owner.respond_to?(:document_folder) || owner_type == "Folder"
  }

  def investors
    if access_to_category.present?
      entity.investors.where(category: access_to_category)
    else
      investor ? [investor] : []
    end
  end

  # Category rights ("All Stakeholders of Specific Category") cover every investor of a
  # category, so one contact can map to several of them.
  #
  # Deliberately still exactly ONE row per contact here - same count as before this change.
  # A category right is a single access right; splitting it per investor would multiply mail
  # volume for every tenant using it, which is not what the per-access-right rule asked for.
  # The stakeholder is attached only when it is unambiguous (the contact maps to exactly one
  # investor of this category); when it is ambiguous the pair carries no investor, so the cc
  # lookup falls back to today's behaviour rather than guessing.
  #
  # Starts from #users so the recipient set stays byte-identical to today's - that query has
  # its own quirks (it filters on users.entity_id, not investor_accesses.entity_id) and
  # changing who receives mail is not this change's job.
  def category_recipients
    category_investors = investors.index_by(&:id)
    return users.map { |contact| [contact, nil] } if category_investors.empty?

    # One query for the whole category rather than per user - #users is already flagged as
    # inefficient upstream; no need to add an N+1 underneath it.
    by_email = InvestorAccess.approved
                             .where(entity_id:, investor_id: category_investors.keys)
                             .pluck(:email, :investor_id)
                             .group_by { |email, _| email.to_s.downcase }

    users.map do |contact|
      investor_ids = by_email[contact.email.to_s.downcase].to_a.map(&:last).uniq
      [contact, investor_ids.one? ? category_investors[investor_ids.first] : nil]
    end
  end

  # Changed: Module 10 — guard for NDA signatory auto-tag callback.
  # Why: Only folder-level AccessRights targeting an investor (direct or category) should
  #   trigger NDA signatory auto-tagging. Non-folder owners (Fund, Deal) and user-level
  #   AccessRights have no NDA relevance.
  #
  # @return [Boolean] true when owner is a Folder and the right targets an investor
  def folder_with_investor?
    owner_type == "Folder" && (access_to_investor_id.present? || access_to_category.present?)
  end

  # Changed: Module 10 — auto-tag NDA signatory when folder AccessRight is granted.
  # Why: Covers the common GP workflow where NDA is set up first, then folder access is granted
  #   to an investor who already has approved InvestorAccess. The InvestorAccess callback misses
  #   this path because InvestorAccess wasn't touched. This callback completes the pair.
  #
  # N+1 analysis:
  #   Query 1: NdaConfig.find_by(owner_type:, owner_id:, enabled:) — indexed, 0-1 rows
  #   Query 2: Investor lookup (direct or category) — 1 query, indexed
  #   Query 3 (per investor): InvestorAccess.where(...).order(:created_at) — indexed
  #   Query 4 (per investor): NdaSignatory.exists?(...) — unique index check
  #   Query 5 (per investor, conditional): NdaSignatory.create! — single insert
  #   Total: 2 + (2-3 per matched investor). Direct AccessRight = 1 investor = 4-5 queries.
  #   Category AccessRight with N investors = 2 + 3N queries. All indexed.
  #
  # @return [void]
  def auto_tag_nda_signatory_for_folder
    # Changed: Look up the NDA config on this specific folder.
    # Why: Only folders with an enabled NDA need signatory auto-tagging.
    nda_config = NdaConfig.find_by(owner_type: "Folder", owner_id: owner_id, enabled: true)
    return unless nda_config

    # Changed: Resolve matched investors — direct or category-based.
    # Why: AccessRight can target a specific investor (access_to_investor_id) or all investors
    #   of a category (access_to_category). Both paths need auto-tag coverage.
    matched_investor_ids = if access_to_investor_id.present?
                             [access_to_investor_id]
                           elsif access_to_category.present?
                             entity.investors.where(category: access_to_category).pluck(:id)
                           else
                             []
                           end
    return if matched_investor_ids.empty?

    matched_investor_ids.each do |inv_id|
      # Changed: Find the oldest approved InvestorAccess user for this investor.
      # Why: Mirrors the controller auto-tag logic — oldest approved user is the default signatory.
      oldest_access = InvestorAccess
                      .where(investor_id: inv_id, entity_id: entity_id, approved: true)
                      .order(:created_at)
                      .first
      next unless oldest_access

      # Changed: Skip if any user of this investor already has a signatory for this NDA.
      # Why: One signatory per investor is sufficient — avoids duplicate rows.
      investor_user_ids = InvestorAccess.where(investor_id: inv_id, entity_id: entity_id, approved: true).select(:user_id)
      next if NdaSignatory.exists?(nda_config_id: nda_config.id, user_id: investor_user_ids)

      # Changed: Tag the oldest approved user. Rescue for race condition idempotency.
      # Why: Two AccessRights created simultaneously could both pass the exists? check.
      NdaSignatory.create!(
        nda_config: nda_config,
        user_id: oldest_access.user_id,
        tagged_by_id: granted_by_id || oldest_access.user_id
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
  end

  def self.grant(owner, investor_id)
    AccessRight.create(owner:, access_to_investor_id: investor_id, entity_id: owner.entity_id)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[access_to_category access_to_investor_id user_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investor user]
  end
end
