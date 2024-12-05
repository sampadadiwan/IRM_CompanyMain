Feature: SOA Generation
  Can create a SOA for Capital Commitment

Scenario Outline: Generate SOA for a Capital Commitment
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
  Given the fund has a template "Commitment level SOA" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "Commitment level SOA" is successfully generated

  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Generated SOA must have templates permssions
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
    Given the fund has a template "Commitment level SOA" of type "SOA Template"
    And the template has permissions "<permissions>"
    And we Generate SOA for the first capital commitment
    Then the "Commitment level SOA" is successfully generated
    And the generated SOA has permissions "<permissions>"

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

Scenario Outline: Unapproved SOA is replaced for a Capital Commitment
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
  Given the fund has a template "Commitment level SOA" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "Commitment level SOA" is successfully generated
  And we Generate SOA for the first capital commitment again
  Then the "Commitment level SOA" is successfully generated
  And the unapproved SOA is replaced
  Given the generated SOA is approved
  Then we Generate SOA for the first capital commitment again
  Then we get the email with approved document exists error
  Then we Generate SOA for the first capital commitment with different time
  Then the "Commitment level SOA" is successfully generated

  Examples:
    |user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |


Scenario Outline: Send Generated SOA for Esign
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
  Given the fund has a template "SOA Template" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "SOA Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures
  And the document is signed by the signatories
  Then the esign log is present
  Then the esign completed document is present


  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Send Generated SOA for Esign with status requested
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
  Given the fund has a template "SOA Template" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "SOA Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures with status "requested"
  And the document is signed by the signatories
  Then the esign completed document is present


  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Send Generated SOA for Esign with status empty
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
  Given the fund has a template "SOA Template" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "SOA Template" is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures with status ""
  And the document is signed by the signatories
  Then the esign completed document is present


  Examples:
  	|user	    |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |

Scenario Outline: Send Generated SOA for Esign with callbacks
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
    Given the fund has a template "SOA Template" of type "SOA Template"
    And we Generate SOA for the first capital commitment
    Then the "SOA Template" is successfully generated
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
  Given the fund has a template "SOA Template" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "SOA Template" is successfully generated
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
  Given the fund has a template "SOA Template" of type "SOA Template"
  And we Generate SOA for the first capital commitment
  Then the "SOA Template" is successfully generated
  Then when the document is approved
  And the document is partially signed by Docusign
  And the docusign document esign is cancelled
  Then the docusign document can be resent for esign

  Examples:
  |user	      |entity                         |role       |given  |should	|access | crud |
  |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |
