Feature: Incoming Email
  Can receive incoming emails and log them to the DB

Scenario Outline: Receive a new email
  Given Im logged in as a user "" for an entity ""
  Given the entity_setting has "<entity_setting>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1"
  Given there is an incoming email sent for this investor "<email>"
  When then the email should be "<added>" to the investor

  Examples:
    | email                                                                   | entity_setting                | added |
    | to=investor.1@dev.caphive.app;from=test1@example.com;subject=Test 123   |                               | true |
    | to=incoming@myentity.com;from=test2@example.com;subject=Investor 1      | mailbox=incoming@myentity.com | true |
    | to=incoming@myentity.com;from=test2@example.com;subject=Wrong Inv Name  | mailbox=incoming@myentity.com | false |
