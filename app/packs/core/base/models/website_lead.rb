# A demo request submitted from the public website.
#
# See docs/modules/website/website_lead_capture.md. Written only by WebsiteLeadCreate,
# which is reached from the one unauthenticated write endpoint in this app
# (WebsiteLeadsController#create). Read only by CapHive staff — the record has no
# entity_id, so WebsiteLeadPolicy gates on role instead of tenancy.
class WebsiteLead < ApplicationRecord
  # Caps on everything a stranger can type. Enforced here rather than only in the
  # database so an oversized field comes back as a 422 with a message, not a
  # truncation (MySQL) or a bloated row (SQLite). MESSAGE_MAX is generous on
  # purpose: this field is the reason the form exists and a prospect describing a
  # complicated fund structure should never hit a wall.
  NAME_MAX     = 200
  EMAIL_MAX    = 255
  FIRM_MAX     = 200
  ROLE_MAX     = 100
  MESSAGE_MAX  = 5_000
  UTM_MAX      = 255
  URL_MAX      = 500
  USER_AGENT_MAX = 512

  # The UTM set, in one place — the operation, the admin view and the purge task
  # all iterate it rather than repeating five column names.
  UTM_FIELDS = %i[utm_source utm_medium utm_campaign utm_content utm_term].freeze

  validates :name,  presence: true, length: { maximum: NAME_MAX }
  validates :email, presence: true, length: { maximum: EMAIL_MAX }
  validates :firm,    length: { maximum: FIRM_MAX },    allow_blank: true
  validates :role,    length: { maximum: ROLE_MAX },    allow_blank: true
  validates :message, length: { maximum: MESSAGE_MAX }, allow_blank: true
  validates :landing_page, :referrer, length: { maximum: URL_MAX }, allow_blank: true
  validates :user_agent,   length: { maximum: USER_AGENT_MAX },     allow_blank: true
  validates(*UTM_FIELDS, length: { maximum: UTM_MAX }, allow_blank: true)

  # Deliberately loose. This is the only field that must be well-formed, but the
  # goal is to catch a typo, not to adjudicate RFC 5322 — a real prospect bounced
  # by an over-strict pattern costs far more than a bad row we can delete.
  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: "is not a valid email address" }

  validates :submitted_at, presence: true

  # Newest first, which is the only order the admin index ever wants.
  scope :recent_first, -> { order(submitted_at: :desc) }

  # Rows whose abuse-control data is older than the retention window and should
  # be stripped. Keyed off submitted_at (the server clock) rather than created_at
  # so the window means what the privacy policy says it means.
  #
  # request_ip IS NOT NULL rather than a blanket update: the task runs daily and
  # would otherwise rewrite every historical row forever.
  scope :abuse_data_expired, lambda { |as_of = Time.current|
    where(submitted_at: ...(as_of - WebsiteLeadRetention::ABUSE_DATA_WINDOW))
      .where.not(request_ip: nil)
  }

  # Leads past the full retention window, deleted outright.
  scope :expired, lambda { |as_of = Time.current|
    where(submitted_at: ...(as_of - WebsiteLeadRetention::LEAD_WINDOW))
  }

  # The stored JSON blob, decoded for display. Returns {} rather than raising —
  # this is diagnostic data on an admin screen, and a malformed blob must not be
  # able to take the page down.
  def raw_payload_hash
    return {} if raw_payload.blank?

    JSON.parse(raw_payload)
  rescue JSON::ParserError
    {}
  end

  # True when any UTM value was captured, so the admin view can hide an empty
  # attribution block instead of printing five dashes.
  def attributed?
    UTM_FIELDS.any? { |field| self[field].present? }
  end
end
