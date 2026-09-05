@doc_gen
Feature: Call notice generation with duplicate call templates
  A fund that ended up with two live "Call Template" documents sharing one name (a revised
  template uploaded without deleting the old one) used to make call-notice generation render a
  notice, delete it, then render it again for every remittance - investors saw the first notice
  link go "access denied" seconds after it appeared. The lookup now collapses same-named
  templates to the newest one, and uploading such a duplicate is rejected up front.

Scenario Outline: Legacy duplicate call templates render exactly one notice per remittance
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the investors are added to the fund
  And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
  When I create a new capital call "<call>"
  Then the corresponding remittances should be created
  Given each investor has a "verified" kyc linked to the commitment
  Given the fund has capital call template
  And the fund also has a legacy duplicate of the capital call template
  And when the capital call docs are generated
  Then each remittance must have exactly one call notice from the newest call template and no deleted notices

  Examples:
    | entity                                                                      | fund                        | call                                                     |
    | entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR | name=SAAS Fund;currency=INR | percentage_called=20;call_basis=Percentage of Commitment |

Scenario Outline: Uploading a second call template with the same name is rejected
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  Given the fund has capital call template
  When I try to upload another template "Call Doc" of type "Call Template" from "Drawdown notice format.docx" for the fund
  Then the template upload must be rejected as a duplicate
  And the fund must still have exactly one "Call Template" template named "Call Doc"

  Examples:
    | entity                                                                      | fund                        |
    | entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR | name=SAAS Fund;currency=INR |
