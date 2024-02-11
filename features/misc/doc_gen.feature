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
  Given the fund has a SOA template "name=SOA template"
  And we Generate SOA for the first capital commitment
  Then it is successfully generated

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
  Given the fund has a SOA template "name=SOA template"
  And we Generate SOA for the first capital commitment
  Then it is successfully generated
  Then when the document is approved
  And the document has "2" e_signatures
  And the document is signed by the signatories
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
  Given the fund has a SOA template "name=SOA template"
  And we Generate SOA for the first capital commitment
  Then it is successfully generated
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
  Given the fund has a SOA template "name=SOA template"
  And we Generate SOA for the first capital commitment
  Then it is successfully generated
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
    Given the fund has a SOA template "name=SOA template"
    And we Generate SOA for the first capital commitment
    Then it is successfully generated
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
    Given the fund has a Commitment template "name=Commitment template"
    And we Generate Commitment template for the first capital commitment
    And it is successfully generated
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
    Given the fund has a Commitment template "name=Commitment template"
    And we Generate Commitment template for the first capital commitment
    And it is successfully generated
    Then when the document is approved
    Then the document has esignatures based on the template
    And the document is partially signed
    And the document esign is cancelled
    Then the document and esign status is cancelled


    Examples:
    |user	      |entity                         |role       |given  |should	|access | crud |
    |  	        |entity_type=Investment Fund  |investor   |yes   |true   |show,edit,update,destroy     | create,read,update,destroy |
