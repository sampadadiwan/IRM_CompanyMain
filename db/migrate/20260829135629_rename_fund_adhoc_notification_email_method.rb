class RenameFundAdhocNotificationEmailMethod < ActiveRecord::Migration[8.1]
  # Fund-owned CustomNotification rows previously routed through the generic, inherited
  # ApplicationMailer#adhoc_notification action. CapitalCommitmentMailer now defines its own
  # explicit adhoc_fund_notification method (see capital_commitment_mailer.rb), so the "For
  # Notification" dropdown shows "Adhoc Fund Notification" instead of "Adhoc Notification".
  #
  # Scoped to owner_type: "Fund" only — Deal and SecondarySale rows also use the literal
  # email_method "adhoc_notification" (their own, unrelated mailer actions) and must be left alone.
  def up
    execute <<~SQL.squish
      UPDATE custom_notifications
      SET email_method = 'adhoc_fund_notification'
      WHERE owner_type = 'Fund' AND email_method = 'adhoc_notification'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE custom_notifications
      SET email_method = 'adhoc_notification'
      WHERE owner_type = 'Fund' AND email_method = 'adhoc_fund_notification'
    SQL
  end
end
