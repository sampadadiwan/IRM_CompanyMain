# Live check against the real Microsoft Graph API -- not part of the default suite.
# Run explicitly, in an environment whose credentials
# (M365_TENANT_ID/M365_CLIENT_ID/M365_CLIENT_SECRET/M365_DRIVE_ID) are expected to be
# live and valid, e.g.:
#   RAILS_ENV=staging bundle exec cucumber --no-profile --tags @m365_live
#
# Exists to catch a broken app secret, a lapsed/removed M365 license, or a Graph API
# regression before it silently blocks document generation for M365-routed templates --
# see docs/modules/documents/m365_graph_pdf_conversion.md.
@m365 @m365_live @rack_test
Feature: M365 Graph PDF conversion stays healthy

  Scenario: Converting a docx via Microsoft Graph produces a valid PDF
    When I convert a sample docx to PDF via the M365 Graph engine
    Then the M365 conversion should succeed
    And the resulting PDF file should be non-empty
