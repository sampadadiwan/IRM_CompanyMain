@notification
Feature: CustomNotifications
  Test behavior of the Custom Notifications


@rack_test
Scenario Outline: Approval Notifications
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is an approval "<approval>" for the entity
  Given the investors are added to the approval  
  Then the approval responses are generated with status "Pending"  
  Given there is a custom notification in place for the approval with subject "<subject>" with email_method "notify_new_approval"
  When the approval is approved internally    
  Then the investor gets the approval custom notification
  Given there is a custom notification in place for the approval with subject "<reminder>" with email_method "approval_reminder"
  When the approval reminder is sent internally
  Then the investor gets the approval custom notification

  Examples:
  	|user	    |entity               |approval                 |msg	|   subject | reminder |
  	|  	        |entity_type=Company  |title=Test approval;enable_approval_show_kycs=true;response_enabled_email=true      |Approval was successfully created| Please respond to approval| Reminder 1 |
    |  	        |entity_type=Company  |title=Merger Approval;enable_approval_show_kycs=false;response_enabled_email=false    |Approval was successfully created| Approval from XYZ| Reminder 2 |


@rack_test
Scenario: Custom notification body placeholders are substituted safely, without ERB
  Given there is a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is an existing investor "" with "1" users
  Given there is an approval "title=Placeholder Approval;enable_approval_show_kycs=false;response_enabled_email=false" for the entity
  Given the investors are added to the approval
  Then the approval responses are generated with status "Pending"
  Given there is a custom notification with placeholders in place for the approval with subject "Please respond" with email_method "notify_new_approval"
  When the approval is approved internally
  Then the investor gets the approval custom notification with placeholders substituted


@rack_test
Scenario Outline: KYC Notifications - not investor_user
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given there is a custom notification "<custom_notification_new>" in place for the KYC 
  Given there is a custom notification "<custom_notification_reminder>" in place for the KYC 
  Given a InvestorKyc is created with details "<kyc>" by "<investor_user>"
  And notification should be sent "<kyc_form_sent>" to the investor for "<custom_notification_new>"
  And notification should be sent "false" to the user for "<custom_notification_update>"
  Given the kyc reminder is sent to the investor
  And notification should be sent "true" to the investor for "<custom_notification_reminder>"


  Examples:
    |kyc_form_sent| kyc                                     | investor_user | custom_notification_new|custom_notification_update|custom_notification_reminder|
    |true         | PAN=ABCD9870;send_kyc_form_to_user=true | false         |  subject=KYC New 1;email_method=notify_kyc_required | subject=KYC Updated 1;email_method=notify_kyc_updated | subject=KYC Reminder 1;email_method=kyc_required_reminder |
    |true         | PAN=ABCD9876;send_kyc_form_to_user=true| false          |  subject=KYC New 2;email_method=notify_kyc_required | subject=KYC Updated 2;email_method=notify_kyc_updated | subject=KYC Reminder 1;email_method=kyc_required_reminder |


@rack_test
Scenario Outline: KYC Notifications - investor_user
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given there is a custom notification "<custom_notification_update>" in place for the KYC 
  Given there is a custom notification "<custom_notification_reminder>" in place for the KYC 
  Given a InvestorKyc is created with details "<kyc>" by "<investor_user>"
  And notification should be sent "false" to the investor for "<custom_notification_new>"
  And notification should be sent "true" to the user for "<custom_notification_update>"

  Examples:
    |kyc_form_sent| kyc                                     | investor_user | custom_notification_new|custom_notification_update|custom_notification_reminder|
    |true         | PAN=ABCD9870;send_kyc_form_to_user=true | true         | subject=KYC New 1;email_method=notify_kyc_required | subject=KYC Updated 1;email_method=notify_kyc_updated | subject=KYC Reminder 1;email_method=kyc_required_reminder |
    |true         | PAN=ABCD9876;send_kyc_form_to_user=true| true          | subject=KYC New 2;email_method=notify_kyc_required | subject=KYC Updated 2;email_method=notify_kyc_updated | subject=KYC Reminder 1;email_method=kyc_required_reminder |

@rack_test
Scenario Outline: KYC notification placeholder substitution
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given there is a custom notification with placeholders for the KYC with subject "<subject>" and email_method "notify_kyc_required"
  Given a InvestorKyc is created with details "PAN=KYC1234;send_kyc_form_to_user=true" by "false"
  Then the KYC notification placeholders are resolved correctly for "notify_kyc_required"

  Examples:
    | subject |
    | KYC Placeholder Test |

@rack_test
Scenario Outline: Custom Notifications - update latest
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given there is a custom notification "<custom_notification_update>" in place for the KYC 
  Then the first notification has latest "true" and enable "true"
  Given there is a custom notification "<custom_notification_update>" in place for the KYC 
  Then the first notification has latest "false" and enable "true"
  Then the second notification has latest "true" and enable "true"
Examples:
    |kyc_form_sent| kyc                                     | custom_notification_update|
    |true         | PAN=ABCD9870;send_kyc_form_to_user=true | subject=KYC Updated 1;email_method=notify_kyc_updated |
    |true         | PAN=ABCD9876;send_kyc_form_to_user=true | subject=KYC Updated 2;email_method=notify_kyc_updated | 


@import
Scenario Outline: Capital call with custom notification
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund" 
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Given there is a custom notification "<custom_notification_new>" in place for the Call 
  Then when the capital call is approved
  And the capital call notifications are sent
  And notification should be sent "true" to the remittance investors for "<custom_notification_new>"

  Examples:
    | custom_notification_new|
    | subject=Remittance is due for fund;email_method=notify_capital_remittance |

@import
Scenario: Capital call notification placeholder substitution
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Given there is a custom notification with placeholders in place for the Call with email_method "notify_capital_remittance"
  Then when the capital call is approved
  And the capital call notifications are sent
  Then the capital remittance notification placeholders are resolved correctly


@import
Scenario: Capital call notification without a custom notification shows the due date as Mon dd, yyyy
  # No custom notification is set up for this call, so notify_capital_remittance.html.erb
  # falls back to its hardcoded <% else %> branch (l @capital_remittance.capital_call.due_date)
  # instead of the custom_notifications/mail partial exercised above — a distinct code path.
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Then when the capital call is approved
  And the capital call notifications are sent
  Then the remittance investors should receive an email with the due date shown as Mon dd, yyyy


@import
Scenario Outline: Capital call notification falls back to the fund-level default
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Given there is a custom notification "<fund_default>" in place for the Fund for Calls
  Then when the capital call is approved
  And the capital call notifications are sent
  And notification should be sent "true" to the remittance investors for "<fund_default>"
  Then the remittance investors should receive an email with subject including "<subject>"

  Examples:
    | fund_default                                                                    | subject                        |
    | subject=Fund default remittance notice;email_method=notify_capital_remittance   | Fund default remittance notice |


@import
Scenario Outline: Capital call specific notification overrides the fund-level default
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Given there is a custom notification "<fund_default>" in place for the Fund for Calls
  Given there is a custom notification "<call_specific>" in place for the Call
  Then when the capital call is approved
  And the capital call notifications are sent
  Then the remittance investors should receive an email with subject including "<subject>"

  Examples:
    | fund_default                                                                    | call_specific                                                                   | subject                       |
    | subject=Fund default remittance notice;email_method=notify_capital_remittance   | subject=Call specific remittance notice;email_method=notify_capital_remittance  | Call specific remittance notice |


Scenario: Fund notifications tab offers a Call and a Distribution notification option
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  Given I open the fund notifications tab
  Then the new notification dropdown should offer "New Fund Notification"
  And the new notification dropdown should offer "New Call Notification"
  And the new notification dropdown should offer "New Distribution Notification"
  When I click "New Call Notification" in the new notification dropdown
  Then the custom notification form should target owner_type "Fund" and for_type "CapitalCall"
  And the custom notification form title should include "Call Notification"

Scenario: Attachment checkboxes are hidden until attachment_names has a value
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  Given I open the fund notifications tab
  When I click "New Call Notification" in the new notification dropdown
  Then the attachment checkboxes should be hidden
  When I fill in "custom_notification_attachment_names" with "Statement of Account"
  Then the attachment checkboxes should be visible
  When I fill in "custom_notification_attachment_names" with ""
  Then the attachment checkboxes should be hidden


@import
Scenario: Capital call notifications tab offers only a call-specific notification option
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Given I open the capital call notifications tab
  Then the new notification dropdown should offer "New Call Notification"
  And the new notification dropdown should not offer "New Fund Notification"
  And the new notification dropdown should not offer "New Distribution Notification"
  When I click "New Call Notification" in the new notification dropdown
  Then the custom notification form should target owner_type "CapitalCall" and for_type ""
  And the custom notification form title should include "Call Notification"


@import
Scenario Outline: Creating a call-specific notification warns when the fund already has a default for that email
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Given there is a custom notification "<fund_default>" in place for the Fund for Calls
  Given I open the capital call notifications tab
  When I click "New Call Notification" in the new notification dropdown
  When I select "Notify capital remittance" as the notification email type
  Then I should see a warning that the fund default will be overridden
  When I select "Notify capital remittance payment" as the notification email type
  Then I should not see a warning about overriding the fund default

  Examples:
    | fund_default                                                                    |
    | subject=Fund default remittance notice;email_method=notify_capital_remittance   |


@notification
Scenario Outline: Capital distribution notification falls back to the fund-level default
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10000000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  Given there is a custom notification "<fund_default>" in place for the Fund for Distributions
  When the capital distribution notifications are sent
  Then the investors must receive email with subject "<subject>" with the document "" attached

  Examples:
  	|user	    |entity                                         |fund                 |fund_default                                                              |subject                          |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund       |subject=Fund default distribution notice;email_method=send_notification  |Fund default distribution notice |


@notification
Scenario Outline: Capital distribution notifications tab offers only a distribution-specific notification option
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10000000;"
  Then I should see the capital distrbution details
  Given I open the capital distribution notifications tab
  Then the new notification dropdown should offer "New Distribution Notification"
  And the new notification dropdown should not offer "New Fund Notification"
  And the new notification dropdown should not offer "New Call Notification"
  When I click "New Distribution Notification" in the new notification dropdown
  Then the custom notification form should target owner_type "CapitalDistribution" and for_type ""
  And the custom notification form title should include "Distribution Notification"

  Examples:
  	|user	    |entity                                         |fund                 |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund       |


@notification
Scenario Outline: Creating a distribution-specific notification warns when the fund already has a default for that email
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10000000;"
  Then I should see the capital distrbution details
  Given there is a custom notification "<fund_default>" in place for the Fund for Distributions
  Given I open the capital distribution notifications tab
  When I click "New Distribution Notification" in the new notification dropdown
  Then I should see a warning that the fund default will be overridden

  Examples:
  	|user	    |entity                                         |fund                 |fund_default                                                              |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund       |subject=Fund default distribution notice;email_method=send_notification  |


@notification @rack_test
Scenario: Preview button on a custom notification shows the rendered email for the first available record
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=SAAS Fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is an adhoc custom notification for the fund with subject "Q4 Update"
  Given I visit the custom notification show page
  Then I see a Preview button on the custom notification page
  When I click the Preview button on the custom notification page
  Then I see the notification preview with subject "Q4 Update"


@notification
Scenario: Preview button is hidden when there is no record yet to preview against
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  Given there is an adhoc custom notification for the fund with subject "No Commitments Yet"
  Given I visit the custom notification show page
  Then I do not see a Preview button on the custom notification page


@notification
Scenario: Preview button is hidden for a Send Document notification, which has no preview route wired up yet
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  Given there is a Custom Notification for the entity
  Given I visit the custom notification show page
  Then I do not see a Preview button on the custom notification page


@notification @rack_test
Scenario: Preview button resolves a KYC notification to the investor's own InvestorKyc record
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given there is a custom notification "subject=KYC New 1;email_method=notify_kyc_required" in place for the KYC
  Given a InvestorKyc is created with details "PAN=ABCD9870;send_kyc_form_to_user=true" by "false"
  Given I visit the custom notification show page
  Then I see a Preview button on the custom notification page
  When I click the Preview button on the custom notification page
  Then I see the notification preview with subject "KYC New 1"


# Regression: InvestorKycMailer had no custom_notification_documents_owner override, so the
# preview (which builds no Noticed::Notification) resolved a nil owner and listed zero
# attachments even though the real send would attach the attachment_names match.
@notification @rack_test
Scenario: KYC notification preview lists the document that attachment_names would attach
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given there is a custom notification "subject=KYC New 1;email_method=notify_kyc_required;attachment_names=PAN Card" in place for the KYC
  Given a InvestorKyc is created with details "PAN=ABCD9870;send_kyc_form_to_user=false" by "false"
  And the investor kyc has document "PAN Card" with file "sample_kyc1.pdf"
  Given I visit the custom notification show page
  When I click the Preview button on the custom notification page
  Then I see the notification preview with subject "KYC New 1"
  And I see "PAN Card" listed as an attachment in the preview


@notification
Scenario Outline: Capital distribution specific notification overrides the fund-level default
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10000000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  Given there is a custom notification "<fund_default>" in place for the Fund for Distributions
  Given there is a custom notification for the capital distribution with subject "<dist_subject>" with email_method "send_notification"
  When the capital distribution notifications are sent
  Then the investors must receive email with subject "<dist_subject>" with the document "" attached

  Examples:
  	|user	    |entity                                         |fund                 |fund_default                                                              |dist_subject                  |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund       |subject=Fund default distribution notice;email_method=send_notification  |Distribution specific notice  |


@rack_test
Scenario Outline: Incoming Email for a capital commitment
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund" 
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  When we receive an incoming email "<email>" for the commitments from sendgrid
  Then an incoming email is created for the commitments
  And the documents are attached to the incoming email

  Examples:
    | entity               | fund               | email |
    | entity_type=Company  | name=SAAS Fund     | subject=Incoming Email 1;body=Incoming Email 1;attachment=capital_commitments.xlsx |
    | entity_type=Company  | name=SAAS Fund     | subject=Incoming Email 2;body=Incoming Email 2;attachment=capital_commitments.xlsx |
