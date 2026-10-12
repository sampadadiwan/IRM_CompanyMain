@rack_test
Feature: Portfolio Investment Report Email Isolation
  PortfolioInvestmentsXlReportJob sends the generated report via its own
  "send_portfolio_investment_report" email_method (DocumentMailer), distinct from the generic
  "send_document" email_method used whenever any other document is shared with a user.
  entity.custom_notification(email_method) matches purely on email_method with no awareness of
  what kind of document is being sent, so without this isolation an unrelated CustomNotification
  configured for "send_document" (e.g. for Statement of Account emails) would hijack the report's
  subject/body - or, if its attachment_password chain didn't apply to the report's owner type,
  crash the send outright.

Scenario: An unrelated Send Document notification does not hijack the report email
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Test fund;currency=INR" for the entity
  Given there is a Custom Notification for the entity with subject "Statement of Accounts" for email_method "send_document"
  When I run the portfolio investment report job for the fund
  Then the portfolio investment report email subject should not be "Statement of Accounts"
  And the portfolio investment report email should have an attachment

Scenario: An entity can configure its own notification scoped to the report's email_method
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Test fund;currency=INR" for the entity
  Given there is a Custom Notification for the entity with subject "Custom Portfolio Report Subject" for email_method "send_portfolio_investment_report"
  When I run the portfolio investment report job for the fund
  Then the portfolio investment report email subject should be "Custom Portfolio Report Subject"
