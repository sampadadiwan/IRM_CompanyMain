# L6 — signing out closes the user's open live-update sockets, so a page left open after logout stops
# receiving the firm's broadcasts. Password change and deactivation do the same from the User model
# (User#disconnect_cable_connections). docs/security/security_review_2026_10.md (L6)
Warden::Manager.before_logout do |user, _auth, opts|
  # Only Devise's :user scope identifies cable sockets (ApplicationCable::Connection)
  next unless opts[:scope] == :user && user.respond_to?(:disconnect_cable_connections)

  user.disconnect_cable_connections
end
