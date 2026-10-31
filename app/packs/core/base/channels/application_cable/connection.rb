module ApplicationCable
  # L6 — a socket belongs to a known user: the signed-in user, or a magic-link visitor within
  # UploadAccess::UPLOAD_WINDOW (KPI / KYC pages subscribe to live updates while signed out).
  # Anyone else is refused. Sockets are closed again on logout, deactivation and password change
  # (config/initializers/action_cable_disconnect.rb, User#disconnect_cable_connections).
  # Stream names are unchanged (Decision: no expiry). Tests L6-1, L6-H —
  # features/security/security_review_2026_10_low.feature
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # Signed in through Devise, or a recent magic-link visit; otherwise the socket is refused (L6-1)
      UploadAccess.warden_user(request) || UploadAccess.signed_id_user(request) || reject_unauthorized_connection
    end
  end
end
