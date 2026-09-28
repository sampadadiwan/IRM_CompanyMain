# Pinning the recipients of a document notification in a scenario.
#
# Senders resolve [user, investor] PAIRS via Document#notification_recipients, not bare users -
# the investor is what supplies that stakeholder's cc addresses (see
# docs/modules/notifications/document_notification_cc_resolution.md). Document#notification_users
# still exists as the distinct-people view, but nothing in the send path calls it, so stubbing
# only that leaves the real access-right resolution running and the scenario fails with
# "No users to send <doc> to".
#
# Stub both through this helper so a scenario pins the recipients whichever accessor the code
# under test reaches for, and so the next stub site cannot miss one.
#
# Pass an investor when the scenario cares about the cc addresses; the default of nil models an
# access right granted directly to a named user (an employee), which carries no stakeholder.
def stub_document_notification_recipients(*users, investor: nil)
  pairs = users.map { |user| [user, investor] }
  allow_any_instance_of(Document).to receive(:notification_recipients).and_return(pairs)
  allow_any_instance_of(Document).to receive(:notification_users).and_return(users)
end
