Feature: CustomNotifications
  Test behavior of the Custom Notifications


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
  And notification should be sent "true" to the remittance investors for "<custom_notification_new>"

  Examples:
    | custom_notification_new|
    | subject=Remittance is due for fund;email_method=notify_capital_remittance |