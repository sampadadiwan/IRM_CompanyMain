Feature: Developer error emails carry a "who / what / where" report
  Every error email sent to the developer inbox (ExceptionNotifier) carries one readable block
  under data[:report], built by ErrorReportContext: web request errors (for_request), Sidekiq job
  failures (for_sidekiq) and handled errors reported from code (ErrorReport.notify).

  Background:
    Given there is an entity "name=ErrRptFund;entity_type=Investment Fund"
    And there is a user "email=err_rpt_admin@example.com;first_name=Asha" for the entity "name=ErrRptFund"
    And the user "err_rpt_admin@example.com" has role "company_admin"

  @error_report
  Scenario: A web request error shows who, where they were switched in, and who was impersonating
    Given there is an entity "name=ErrRptAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=err_rpt_advisor@example.com" for the entity "name=ErrRptAdvisorFirm"
    And the user "err_rpt_advisor@example.com" has role "investor_advisor"
    And the advisor "err_rpt_advisor@example.com" is switched into entity "name=ErrRptFund"
    And there is a user "email=err_rpt_support@example.com" for the entity "name=ErrRptFund"
    When an error report is built for a request to "/investor_kycs/12" by "err_rpt_advisor@example.com" impersonated by "err_rpt_support@example.com"
    Then the error report shows "Source" as "ErrorReportFakeController#show"
    And the error report shows "Request" as "GET /investor_kycs/12"
    And the error report shows "User" as "err_rpt_advisor@example.com"
    And the error report shows "Switched into" as "ErrRptFund"
    And the error report shows "Home firm" as "ErrRptAdvisorFirm"
    And the error report shows "Roles" as "investor_advisor"
    And the error report shows "Impersonated by" as "err_rpt_support@example.com"

  @error_report
  Scenario: A web request report is only built if the request fails and the email is printed
    When a request error report is attached but nothing has printed it
    Then nothing has been looked up for the report yet
    When the error email prints its data
    Then the report has been built exactly once

  @error_report
  Scenario: A Sidekiq failure names the job, who triggered it and from where, without ActiveJob noise
    When an error report is built for a failed Sidekiq NotifyKycJob enqueued by "err_rpt_admin@example.com"
    Then the error report shows "Source" as "NotifyKycJob"
    And the error report shows "Triggered by" as "err_rpt_admin@example.com"
    And the error report shows "Triggered from" as "app/packs/core/investor_kycs/models/investor_kyc.rb:292"
    And the error report shows "Job arguments" as "1845, email_method: notify_kyc_updated"
    And the error report shows "Retry count" as "2"
    And the error report does not mention "_aj_"

  @error_report
  Scenario: A report that cannot be built still produces a block, so the email is still sent
    When an error report is built from a malformed Sidekiq context
    Then the error report shows "Context" as "unavailable (NoMethodError)"

  @error_report
  Scenario: A handled error reported from inside a job carries the job block and the entity
    When a WeeklyTaskDigestJob reports an error through ErrorReport for entity "ErrRptFund"
    Then the reported error report shows "Source" as "WeeklyTaskDigestJob"
    And the reported error report shows "Entity" as "ErrRptFund"
    And the reported error report shows "Queue" as "low"

  @error_report
  Scenario: A handled error reported without a source names the line that reported it
    When code reports an error through ErrorReport without naming a source
    Then the reported error report shows "Source" as "features/step_definitions/developer_error_report_steps.rb"
