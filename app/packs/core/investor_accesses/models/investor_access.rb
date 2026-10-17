class InvestorAccess < ApplicationRecord
  include Trackable.new
  # LP CRM MVP: an InvestorAccess with approved=false doubles as a CRM contact
  # ("touch point") for a prospective LP — no portal access, no email sent.
  # Contact details beyond name/email/phone (designation, POC role, intro, primary
  # flag, ...) are tenant-configured custom fields stored in json_fields, so we
  # reuse the standard WithCustomField machinery instead of adding columns.
  include WithCustomField

  attr_accessor :call_code

  # Set by InvestorAccessesController#create only, so the UI "add investor access" form
  # cannot grant access to a user who holds the investor_advisor role. Other creation paths
  # (CSV import, self-service request_access, admin panel) do not set this and are unaffected.
  attr_accessor :disallow_investor_advisor

  # Make all models searchable
  update_index('investor_access') { self if index_record? }

  validates :email, :first_name, :last_name, presence: true
  validates :first_name, :last_name, length: { maximum: 255 } # matches users.first_name / users.last_name column size
  validates :email, length: { maximum: 255 }
  validates :tag_list, length: { maximum: 120 }, allow_blank: true
  belongs_to :entity
  belongs_to :investor_entity, class_name: "Entity"
  belongs_to :investor # , strict_loading: true

  belongs_to :user, touch: true
  belongs_to :granter, class_name: "User", foreign_key: :granted_by, optional: true
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  delegate :name, to: :entity, prefix: :entity
  delegate :investor_name, to: :investor

  validates_uniqueness_of :email, scope: :investor_id, message: "Aready added as a stakeholder"
  validates_format_of :email, with: URI::MailTo::EMAIL_REGEXP, multiline: true
  validates :phone, length: { maximum: 15 }, allow_blank: true

  counter_culture :investor, column_name: proc { |model| model.approved ? 'investor_access_count' : 'unapproved_investor_access_count' },
                             column_names: {
                               ["investor_accesses.approved = ?", true] => 'investor_access_count',
                               ["investor_accesses.approved = ?", false] => 'unapproved_investor_access_count'
                             }

  counter_culture :investor, column_name: proc { |model| model.approved && model.email_enabled ? 'will_receive_email' : nil },
                             column_names: {
                               ["investor_accesses.approved=? AND investor_accesses.email_enabled=?", true, true] => 'will_receive_email'
                             }

  scope :with_tag, ->(tag) { where("investor_accesses.tag_list LIKE ?", "%#{tag}%") }

  scope :approved_for_user, lambda { |user, across_all_entities: false|
    if across_all_entities && user.has_cached_role?(:investor_advisor)
      where("investor_accesses.user_id=? and investor_accesses.approved=?", user.id, true).distinct
    else
      where("investor_accesses.investor_entity_id=? and investor_accesses.user_id=? and investor_accesses.approved=?", user.entity_id, user.id, true)
    end
  }

  scope :approved, lambda {
    where("investor_accesses.approved=?", true)
  }

  scope :not_investor_advisors, lambda {
    where("investor_accesses.is_investor_advisor=?", false)
  }

  scope :investor_advisors, lambda {
    where("investor_accesses.is_investor_advisor=?", true)
  }

  scope :unapproved, lambda {
    where("investor_accesses.approved=?", false)
  }

  scope :email_enabled, lambda {
    where("investor_accesses.email_enabled=?", true)
  }

  scope :email_disabled, lambda {
    where("investor_accesses.email_enabled=?", false)
  }

  scope :approved_for, lambda { |user, entity|
                         where("investor_accesses.user_id=? and investor_accesses.entity_id=? and investor_accesses.approved=?", user.id, entity.id, true)
                       }

  EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP
  validate :cc_must_contain_valid_emails
  def cc_must_contain_valid_emails
    return if cc.blank?

    # Split the emails by comma, remove any leading or trailing spaces and reject any blanks
    emails = cc.split(',').map(&:strip).compact_blank
    email_regex = URI::MailTo::EMAIL_REGEXP
    invalid_emails = emails.grep_v(email_regex)

    errors.add(:cc, "contains invalid emails: #{invalid_emails.join(', ')}") if invalid_emails.any?
    # Remove duplicates and join them back
    self.cc = emails.uniq.join(",")
  end

  before_validation :update_user
  validate :ensure_entity_id
  validate :block_investor_advisor_from_ui, if: :disallow_investor_advisor

  # This is to check that a user belonging to entity 1 is not given investor_access in an investor belonging to entity 2
  # This rule however does not hold for investor_advisors. This is because they can switch entity_ids to become
  # the advisor for any entity they have access to
  def ensure_entity_id
    errors.add(:user, "cannot be given access. Belongs to #{user.entity.name} id #{user.entity.id} but is being added to #{investor.investor_entity.name} id #{investor.investor_entity.id}") if user && !user.has_cached_role?(:investor_advisor) && user.entity_id != investor.investor_entity_id
  end

  # is_investor_advisor is set by update_user (before_validation) from the matched/created user's
  # rolify role, so it is already accurate by the time this validation runs.
  #
  # The block keeps CLIENT access on the Add Investor Advisor flow, which also creates the advisor's
  # fund grants. An advisor's OWN firm can be an LP too, and on that record they are a plain contact
  # like their colleagues, so it is allowed. "Own" means the advisor's recorded home
  # (advisor_entity_id), else their entity for a legacy advisor with none - never the client entity
  # they may be switched into right now.
  # The is_investor_advisor flag is left as the role says, so deleting the row still runs
  # remove_advisor_fund_access_rights.
  # Worked examples H1, E1–E4, X1, X2 — openspec/changes/fix-advisor-add-own-lp-contact/report.md#verification
  def block_investor_advisor_from_ui
    return unless is_investor_advisor
    # The advisor's own firm's LP record: allowed (matrix rows 3–5).
    return if user && investor_entity_id == (user.advisor_entity_id || user.entity_id)

    errors.add(:email, "belongs to a user with the Investor Advisor role and cannot be added as investor access from this page")
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def to_s
    email
  end

  def update_user
    self.investor_entity_id = investor.investor_entity_id
    self.email = email.strip
    u = User.find_by(email:)
    if u.blank?
      # Setup a new user for this investor_entity_id
      u = User.new(first_name:, last_name:, email:, active: true,
                   phone:, whatsapp_enabled: true, system_created: true,
                   entity_id: investor.investor_entity_id, password: SecureRandom.hex(8))
      u.call_code = call_code if call_code.present?
      # The number comes from an access row, often imported from a spreadsheet, and this
      # save's result is discarded below. Without the opt-out an unparseable number makes
      # User#phone_must_be_dialable refuse, the belongs_to autosave writes user_id = NULL,
      # and the access row is saved pointing at nobody. See User#skip_phone_validation.
      u.skip_phone_validation = true

      # Save the user
      u.save

      # If this user was created in the process of investor access and is the only user, make him company admin
      # u.add_role :company_admin if u.entity.employees.count == 1
    end
    self.user = u
    self.is_investor_advisor = user.has_cached_role?(:investor_advisor)
  end

  def send_notification
    msg = "You have been granted access to '#{entity.name}'"
    InvestorAccessNotifier.with(record: self, entity_id:, email_method: :notify_access, msg:).deliver_later(user) if URI::MailTo::EMAIL_REGEXP.match?(email)
  end

  def send_notification_if_changed
    send_notification if id.present? && saved_change_to_approved?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[approved created_at email first_name granted_by last_name phone whatsapp_enabled email_enabled is_investor_advisor tag_list].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investor user]
  end

  def parse_cc
    cc&.scan(%r{\b[a-zA-Z0-9.!\#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\b})&.join(",")
  end

  # Changed: Module 10 — auto-tag as NDA signatory when investor access is approved.
  # Why: When new investors are added to a folder after the NDA is already configured, they have
  #   zero signatories and their LPs see the "blocked" page. This callback ensures the first
  #   approved user per investor is auto-tagged for any existing NDA configs on folders they have
  #   access to — matching the on-creation behavior in NdaConfigsController#auto_tag_default_signatories.
  after_commit :auto_tag_nda_signatory_if_needed, on: %i[create update], if: :approved?

  # When an advisor's InvestorAccess is destroyed, revoke their fund-level AccessRight for any
  # fund where they no longer have another active InvestorAccess (i.e. no remaining approved
  # InvestorAccess for investors in that fund via this user).  Previously the cache rebuild
  # handled this; now we clean the AR directly.
  after_commit :remove_advisor_fund_access_rights, on: :destroy, if: :is_investor_advisor?

  # Changed: Module 10 — auto-tags this user as NDA signatory for folder NDAs the investor can access.
  # Why: Without this, investors added after NDA setup have zero signatories and their LPs are blocked.
  #   Scoped to folder-level AccessRight (not entity-wide) to match NdaStatusResolver behavior.
  #
  # N+1 analysis:
  #   Query 1: NdaConfig.where(entity_id:, enabled:, owner_type:) — indexed on entity_id, 1-3 rows typical
  #   Query 2 (per NDA): AccessRight.exists?(...) — indexed on [owner_type, owner_id], existence check only
  #   Query 3 (per NDA): NdaSignatory.exists?(...) — indexed on unique [nda_config_id, user_id]
  #   Query 4 (per NDA, conditional): NdaSignatory.create — single insert
  #   Total: 1 + (2-3 per NDA config). Typical entity has 1-3 NDA configs = 3-10 queries. All indexed.
  #
  # @return [void]
  def auto_tag_nda_signatory_if_needed
    # Changed: Only check enabled NDA configs on folders (not other owner types).
    # Why: NDA signatory gating is folder-specific; other owner types don't use this flow yet.
    nda_configs = NdaConfig.where(entity_id: entity_id, enabled: true, owner_type: "Folder")
    return if nda_configs.none?

    nda_configs.each do |nda_config|
      # Changed: Check folder-level access via AccessRight before tagging.
      # Why: The investor must have an AccessRight on this specific folder — entity-wide access alone
      #   does not grant folder access and should not trigger signatory tagging.
      next unless AccessRight.exists?(
        ["owner_type = ? AND owner_id = ? AND entity_id = ? AND (access_to_investor_id = ? OR access_to_category = ?)",
         "Folder", nda_config.owner_id, entity_id, investor_id, investor.category]
      )

      # Changed: Check if ANY user of this investor already has a signatory for this NDA.
      # Why: One signatory per investor is sufficient — the investor is "covered" once any of their
      #   users is tagged. Avoids redundant signatory rows.
      investor_user_ids = InvestorAccess.where(investor_id: investor_id, entity_id: entity_id, approved: true).select(:user_id)
      next if NdaSignatory.exists?(nda_config_id: nda_config.id, user_id: investor_user_ids)

      # Changed: Use create (not create!) with rescue for idempotency.
      # Why: Race condition — two accesses approved simultaneously could both pass the exists? check.
      #   The unique index on [nda_config_id, user_id] catches the duplicate; we skip silently.
      NdaSignatory.create!(
        nda_config: nda_config,
        user_id: user_id,
        tagged_by_id: granted_by || user_id
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
  end

  def remove_advisor_fund_access_rights
    fund_ids = investor.capital_commitments.pluck(:fund_id).uniq
    return if fund_ids.empty?

    fund_ids.each do |fund_id|
      # Check whether any other approved InvestorAccess still links this user to an investor
      # in this fund ON THE SAME CLIENT ENTITY. The AccessRight revoked below is the one scoped to
      # this investor's entity, so only rows of that entity can still justify it (R3). Counting any
      # investor in the fund kept the removed client's grant alive whenever the advisor also
      # advised another client in the fund, or was themselves an LP of it.
      # Worked example R3 — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
      still_has_access = InvestorAccess
                         .joins(investor: :capital_commitments)
                         .where(user_id: user_id, approved: true, is_investor_advisor: true)
                         .where(investors: { investor_entity_id: investor.investor_entity_id })
                         .where(capital_commitments: { fund_id: fund_id })
                         .where.not(id: id)
                         .exists?

      next if still_has_access

      AccessRight.where(
        entity_id: investor.investor_entity_id,
        owner_type: "Fund",
        owner_id: fund_id,
        user_id: user_id
      ).destroy_all
    end
  end
end
