@notification @attachment
Feature: Email attachment size limit
  As the team running CapHive
  I want every notification that can carry an attachment to be size-checked
  So that an oversized document is never fanned out to an investor list

  # Background to these scenarios: in September 2026 a 20.3 MB PDF was attached to a
  # notification sent to 137 investors. MIME encoding inflates a file by ~137%, so each
  # message left at ~28 MB. SES accepted all of them, then roughly nine in ten deliveries
  # bounced at the receiving mail servers, while CapHive showed every one as "Sent".
  # See docs/operations/troubleshooting/24092026_peercapital_annual_report_email_bounces.md
  #
  # The limit lives in ONE place — ApplicationMailer#attachment_allowed?, reached from
  # attach_doc and pw_protect_attach_file. These scenarios keep that single point of
  # enforcement honest as mailers are added. Per-notification behaviour (which recipients
  # get skipped, what the operator is told) is covered in
  # features/fund/fund_commitment_adhoc_notification.feature.

  # The completeness check. Guarding two methods only covers every notification while no
  # mailer assigns attachments[...] directly — this fails the moment one does, naming the
  # file, rather than letting it silently escape the limit.
  Scenario: No mailer can attach a file without passing the size limit
    Then every mailer attachment site is size-guarded or a known exemption

  # The two methods every Document attachment flows through must actually call the guard.
  # Without this, the scenario above would still pass while the limit did nothing.
  Scenario: The document attachment methods enforce the limit
    Then the document attachment methods all enforce the size limit

  # Pins the rule itself: one oversized document is refused, and several that each fit but
  # together do not are also refused.
  Scenario: The limit rejects a single oversized document and an oversized total
    Then the attachment size limit is enforced at the boundary

  # The send-time guard makes an oversized email impossible everywhere. This is about the
  # other half: every bulk send must also check up front, so the whole run stops at once
  # instead of skipping recipients one at a time and reporting it minutes later.
  Scenario: Every bulk notification send checks attachment sizes before fanning out
    Then every bulk notification send runs the attachment preflight
