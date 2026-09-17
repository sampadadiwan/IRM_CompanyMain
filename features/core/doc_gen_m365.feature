# Same document-generation flows as features/core/doc_gen.feature, but routed through
# M365PdfConversion (Document#pdf_conversion_engine == "m365") instead of the default
# LibreOffice path. Exercises the real Microsoft Graph API, so it needs live
# M365_TENANT_ID/M365_CLIENT_ID/M365_CLIENT_SECRET/M365_DRIVE_ID credentials and is
# tagged @m365_live so it stays out of routine runs, same as features/m365_pdf_conversion.feature.
# See docs/technical/m365_graph_pdf_conversion.md.
@doc_gen @m365 @m365_live
Feature: Investor document generation via the M365 Graph PDF conversion engine

Scenario Outline: Generate Investor Statement for a Capital Commitment via M365
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has "2" capital call
  Given the capital calls are approved
  Given the fund has "2" capital distribution
  Given the capital distributions are approved
  Given the fund has a template "Commitment level Investor Statement" of type "Investor Statement Template"
  Given the template "Commitment level Investor Statement" has attrs "pdf_conversion_engine=m365"
  And we Generate Investor Statement for the first capital commitment
  Then the "Commitment level Investor Statement" is successfully generated

  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Generate Commitment Agreement for a Capital Commitment via M365
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  Given there is a fund "name=Test fund" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has "2" capital call
  Given the capital calls are approved
  Given the fund has "2" capital distribution
  Given the capital distributions are approved
  Given the fund has a template "Commitment Agreement Template2" of type "Commitment Template"
  Given the template "Commitment Agreement Template2" has attrs "pdf_conversion_engine=m365"
  And we Generate Commitment Agreement for the first capital commitment
  Then the "Commitment Agreement Template2" is successfully generated

  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |
