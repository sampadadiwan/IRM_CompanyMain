@doc_gen
Feature: Investor Statement Generation
  Can create a Investor Statement for Capital Commitment

Scenario Outline: Generate Investor Statement for a Capital Commitment
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
  And we Generate Investor Statement for the first capital commitment
  Then the "Commitment level Investor Statement" is successfully generated

  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Generated Investor Statement must have templates permssions
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
    And the template has permissions "<permissions>"
    And we Generate Investor Statement for the first capital commitment
    Then the "Commitment level Investor Statement" is successfully generated
    And the generated Investor Statement has permissions "<permissions>"

    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud | permissions |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |printing=true;orignal=true;download=true|
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |printing=true;orignal=false;download=true|
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |printing=false;orignal=true;download=false|

Scenario Outline: Generate Commitment Agreement for a Capital Commitment
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
  And we Generate Commitment Agreement for the first capital commitment
  Then the "Commitment Agreement Template2" is successfully generated

  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: No Commitment template for a Capital Commitment
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
    And we Generate All Documents for the first capital commitment
    Then we get the email with error "No templates found"

    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Only Unapproved Commitment Agreement is replaced
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
  And we Generate Commitment Agreement for the first capital commitment
  Then the "Commitment Agreement Template2" is successfully generated
  Then we Generate Commitment Agreement for the first capital commitment again
  Then the "Commitment Agreement Template2" is successfully generated
  And the original document is replaced
  Then the last generated document is approved
  Then we Generate Commitment Agreement for the first capital commitment again
  Then we get the email with approved document exists error


  Examples:
    |user	    |entity                         |role       |given  |should	|access | crud |email|
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |Approved document already exists for|

Scenario Outline: Footer error in Generating Commitment Agreement
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
  And we Generate Commitment Agreement for the first capital commitment
  Then the "Commitment Agreement Template2" is successfully generated
  Given the commitment has a corrupted footer for the template
  Then we Generate Commitment Agreement for the first capital commitment with corrupt "header"
  Then we get the email with error "<footer_error>"
  Given the commitment has a corrupted header for the template
  Then we Generate Commitment Agreement for the first capital commitment with corrupt "footer"
  Then we get the email with error "<header_error>"

  Examples:
    |user	    |entity                         |role       |given  |should	|access | crud |email|footer_error|header_error|
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |Approved document already exists for|Error adding Footer:|Error adding Header:|

Scenario Outline: Broken merge field in a template names the specific field in the error email
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
  Given the template "Commitment Agreement Template2" has a corrupted merge field
  And we Generate Commitment Agreement for the first capital commitment
  Then we get the email with error "<merge_field_error>"
  And we get the email with error "<broken_field>"

  Examples:
    |user	    |entity                         |role       |given  |should	|access | crud |merge_field_error|broken_field|
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |Error evaluating template field|investor_kyc.full_name.gsub|

Scenario Outline: Check header footer and append documents merging in Generating Commitment Agreement
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
  Given the template "Commitment Agreement Template2" has attrs "template_docs_to_append=image doc"
  Given the KYC associated with the commitment has the document "image doc" with file "merge test image.jpeg"
  Given the commitment has document "Commitment Agreement Template2 Header" with file "CapHive - CERTIFICATE OF INCORPORATION.PDF"
  And the commitment has document "Commitment Agreement Template2 Header" with file "CapHive - GST Certificate.pdf"
  And the commitment has document "Commitment Agreement Template2 Footer" with file "TEST DOC 3 - 24 Oct 25 - 2.pdf"
  And the commitment has document "Commitment Agreement Template2 Footer" with file "pdf sample with images.pdf"
  And we Generate Commitment Agreement for the first capital commitment
  Then the "Commitment Agreement Template2" is successfully generated
  # from CapHive - CERTIFICATE OF INCORPORATION.PDF
  And the document should contain the text "This certificate only evidences incorporation of the company on the basis of documents"
  # from CapHive - GST Certificate.pdf
  And the document should contain the text "The registration certificate is required to be prominently displayed at all places of business in the State"
  # from pdf sample with images text
  And the document should contain the text "Adobe Acrobat PDF Files"
  # from TEST DOC 3 - 24 Oct 25 - 2.pdf
  And the document should contain the text "Total Commitment Amount (In Words)"
  # from Commitment Agreement Template2
  And the document should contain the text "THIS CONTRIBUTION AGREEMENT (hereinafter referred to as this “Agreement”)"
  # from merge test image.jpeg
  And the document should contain an image with dimensions 1200x800

  Examples:
    |user	    |entity                         |role       |given  |should	|access | crud |email|
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |Approved document already exists for|

Scenario Outline: Unapproved Investor Statement is replaced for a Capital Commitment
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
  And we Generate Investor Statement for the first capital commitment
  Then the "Commitment level Investor Statement" is successfully generated
  And we Generate Investor Statement for the first capital commitment again
  Then the "Commitment level Investor Statement" is successfully generated
  And the unapproved Investor Statement is replaced
  Given the generated Investor Statement is approved
  Then we Generate Investor Statement for the first capital commitment again
  Then we get the email with approved document exists error
  Then we Generate Investor Statement for the first capital commitment with different time
  Then the "Commitment level Investor Statement" is successfully generated

  Examples:
    |user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |


Scenario Outline: Send Generated Investor Statement for Esign
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fund898" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has "2" capital call
  Given the capital calls are approved
  Given the fund has "2" capital distribution
  Given the capital distributions are approved
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  And we Generate Investor Statement for the first capital commitment
  Then the "Investor Statement Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures
  And the document is signed by the signatories
  Then the esign log is present
  Then the esign completed document is present


  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Generate Investor Statement duplicate emails
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fund898;esign_emails=abcg@demo.com" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has "2" capital call
  Given the capital calls are approved
  Given the fund has "2" capital distribution
  Given the capital distributions are approved
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  Given the first capital commitment has params "esign_emails=abcg@demo.com,xyz@demo.com"
  Given the template has esignatures "investor_signatories,fund_signatories,other:xyz@demo.com,other:mnop@demo.com"
  Then The document generation fails with error "E signatures contain duplicate emails: abcg@demo.com, xyz@demo.com"

  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Send Generated Investor Statement for Esign with status requested
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fund895" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has "2" capital call
  Given the capital calls are approved
  Given the fund has "2" capital distribution
  Given the capital distributions are approved
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  And we Generate Investor Statement for the first capital commitment
  Then the "Investor Statement Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures with status "requested"
  And the document is signed by the signatories
  Then the esign completed document is present


  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Send Generated Investor Statement for Esign with status empty
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fund838" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has "2" capital call
  Given the capital calls are approved
  Given the fund has "2" capital distribution
  Given the capital distributions are approved
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  And we Generate Investor Statement for the first capital commitment
  Then the "Investor Statement Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures with status ""
  And the document is signed by the signatories
  Then the esign completed document is present


  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Send Generated Investor Statement for Esign with callbacks
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
    Given there is a fund "name=Test fund828" for the entity
    And another user is "<given>" fund advisor access to the fund
    And the access right has access "<crud>"
    Given the user has role "<role>"
    Given the fund has capital commitments from each investor
    And each Investor has an approved Investor Kyc
    Given the fund has "2" capital call
    Given the capital calls are approved
    Given the fund has "2" capital distribution
    Given the capital distributions are approved
    Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
    And we Generate Investor Statement for the first capital commitment
    Then the "Investor Statement Template" is successfully generated
    Then when the document is approved
    And the document has "2" e_signatures
    And the document get digio callbacks
    Then the esign completed document is present


    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

  Scenario Outline: Generate document from funds template
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
    Given there is a fund "name=Test fund868" for the entity
    And another user is "<given>" fund advisor access to the fund
    And the access right has access "<crud>"
    Given the user has role "<role>"
    Given the fund has capital commitments from each investor
    And each Investor has an approved Investor Kyc
    Given the fund has a template "Commitment Agreement Template2" of type "Commitment Template"
    Given the template has esigns setup
    And we Generate Commitment Agreement for the first capital commitment
    And the "Commitment Agreement Template2" is successfully generated
    Then when the document is approved
    Then the document has esignatures based on the template


    Examples:
    |user	      |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Cancel Esign for a document
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
    Given there is a fund "name=Test fund8685" for the entity
    And another user is "<given>" fund advisor access to the fund
    And the access right has access "<crud>"
    Given the user has role "<role>"
    Given the fund has capital commitments from each investor
    And each Investor has an approved Investor Kyc
    Given the fund has a template "Commitment Agreement Template2" of type "Commitment Template"
    Given the template has esigns setup
    And we Generate Commitment Agreement for the first capital commitment
    And the "Commitment Agreement Template2" is successfully generated
    Then when the document is approved
    Then the document has esignatures based on the template
    And the document is partially signed
    And the document esign is cancelled
    Then the document and esign status is cancelled
    Then the document can be resent for esign


    Examples:
    |user	      |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Docusign Esign for a document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fund898" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the esign provider is "Docusign"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  And we Generate Investor Statement for the first capital commitment
  Then the "Investor Statement Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures by Docusign
  And the document is signed by the docusign signatories
  Then the docusign esign completed document is present

  Examples:
  |user	      |entity                         |role       |given  |should	|access | crud |
  |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Docusign Esign for a document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fund898" for the entity
  And another user is "<given>" fund advisor access to the fund
  And the access right has access "<crud>"
  Given the user has role "<role>"
  Given the esign provider is "Docusign"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  And we Generate Investor Statement for the first capital commitment
  Then the "Investor Statement Template" is successfully generated
  Then when the document is approved
  And the document is partially signed by Docusign
  And the docusign document esign is cancelled
  Then the docusign document can be resent for esign

  Examples:
  |user	      |entity                         |role       |given  |should	|access | crud |
  |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Generated Investor Statement has as_of set to the statement end date
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
  And we Generate Investor Statement for the first capital commitment
  Then the "Commitment level Investor Statement" is successfully generated
  And the generated investor statement has as_of equal to end date

  Examples:
    |user      |entity                       |role     |given |access                       | crud                       |
    |          |entity_type=Investment Fund  |investor |yes   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Bulk Generate Investor Statement for all commitments of fund
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is a fund "name=Test fund828" for the entity
    Given the fund has "3" capital commitments from each investor
    Given the commitments from each investor have the same KYC
    Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
    And we Generate Investor Statements from commitments index page
    Then the "Investor Statement Template" is successfully generated for all intended commitments
    Then the investment statement email is sent


    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Bulk Generate Investor Statement for all but first commitments
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is a fund "name=Test fund828" for the entity
    Given the fund has "3" capital commitments from each investor
    Given the commitments from each investor have the same KYC
    Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
    Given I update the "1" commitments belonging to the same kyc custom fields "skip_doc_gen:Yes"

    And we Generate Investor Statements from commitments index page
    Then the "Investor Statement Template" is successfully generated for all intended commitments
    Then the investment statement email is sent


    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Bulk Generate Investor Statement for only latest commitments of KYC
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is a fund "name=Test fund828" for the entity
    Given the fund has "3" capital commitments from each investor
    Given the commitments from each investor have the same KYC
    Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
    Given I update the "1,2" commitments belonging to the same kyc custom fields "skip_doc_gen:Yes"

    And we Generate Investor Statements from commitments index page
    Then the "Investor Statement Template" is successfully generated for all intended commitments
    Then the investment statement email is sent

    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |


Scenario Outline: Bulk Generate Investor Statement for only latest commitments of KYC
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is a fund "name=Test fund828" for the entity
    Given the fund has "3" capital commitments from each investor
    Given the commitments from each investor have the same KYC
    Given the "1" commitment from each investor has no KYC
    Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
    Given I update the "2" commitments belonging to the same kyc custom fields "skip_doc_gen:Yes"

    And we Generate Investor Statements from commitments index page
    Then the "Investor Statement Template" is successfully generated for all intended commitments
    Then the investment statement email is sent

    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Bulk Generate Investor Statement for only latest commitments of KYC
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an existing investor "entity_type=Family Office"
    Given there is a fund "name=Test fund828" for the entity
    Given the fund has "3" capital commitments from each investor
    Given the commitments from each investor have the same KYC
    Given the "1" commitment from each investor has unverified KYC
    Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
    Given I update the "2" commitments belonging to the same kyc custom fields "skip_doc_gen:Yes"

    And we Generate Investor Statements from commitments index page
    Then the "Investor Statement Template" is successfully generated for all intended commitments
    Then the investment statement email is sent

    Examples:
      |user	    |entity                         |role       |given  |should	|access | crud |
      |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |
