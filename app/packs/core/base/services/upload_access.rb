# Who may reach the direct-upload endpoints (Shrine presign / upload / S3 multipart, L1) and open an
# ActionCable socket (L6): a signed-in user, or a user who opened a magic link (KPI report, KYC)
# within the last UPLOAD_WINDOW. Magic-link users upload their KPI files and KYC documents while
# signed out, so the link's visit is remembered in the session by
# ApplicationController#find_by_signed_id_for_user.
# docs/security/security_review_2026_10.md (Core / misc — Medium and Low, L1 and L6)
module UploadAccess
  # How long after opening a magic link its user may keep uploading / listening (Decision: 2 hours)
  UPLOAD_WINDOW = 2.hours
  # Session keys written by ApplicationController#find_by_signed_id_for_user
  SESSION_USER_KEY = :signed_id_user_id
  SESSION_AT_KEY = :signed_id_at

  module_function

  # Route constraint for the upload mounts. Tests L1-1, L1-2, L1-H, L1-H2 —
  # features/security/security_review_2026_10_low.feature
  def allowed?(request)
    # A signed-in user, or a recent magic-link visitor; anyone else gets a 404
    warden_user(request).present? || signed_id_user(request).present?
  end

  # Remembers a magic-link visit in the session, so the page's uploads and live updates work
  def remember_signed_id_user(session, user)
    session[SESSION_USER_KEY] = user.id
    session[SESSION_AT_KEY] = Time.current.to_i
  end

  # The signed-in user (Devise :user scope), if any
  def warden_user(request)
    request.env["warden"]&.user(:user)
  end

  # The magic-link user of this session, if the link was opened within UPLOAD_WINDOW and the user
  # is still active (deactivation revokes magic links too)
  def signed_id_user(request)
    session = request.session
    user_id = session[SESSION_USER_KEY]
    opened_at = session[SESSION_AT_KEY].to_i
    # No magic link opened in this session
    return nil if user_id.blank? || opened_at.zero?
    # The window has passed (L1-2)
    return nil if Time.zone.at(opened_at) < UPLOAD_WINDOW.ago

    User.active.find_by(id: user_id)
  end
end
