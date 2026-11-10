Feature: OWASP Top 10 review 2026-11 - Critical and High fixes, without changing working behaviour
  Each finding's attack is refused, and the real production values next to it keep working: every stored
  formula, grid key, PDF password field, custom field name and sub_domain shape the fixes were checked against
  (2026-11-09 production copy) has a scenario here.
  Report: docs/security/owasp_top10_review_2026_11.md

  ##############################################################################
  # C1 — formula denylist stopgap (until FORMULA_SANDBOX=enforce)
  ##############################################################################

  # C1-1 — Error case: the four bypasses that got through the denylist are now refused
  @security
  Scenario: C1-1 Formula denylist refuses the known bypasses
    Then the OWASP formula guard refuses:
      | formula                                             |
      | method(("sy"+"stem").to_sym).call("id")             |
      | Rails.application.credentials                       |
      | Investor.unscoped.where(id: 1).pluck(:pan)          |
      | connection.exec_query("SEL"+"ECT 1")                |
      | ObjectSpace.each_object(Class).count                |
      | capital_commitment.instance_variable_get(:@attributes) |

  # C1-H — Happy path: formula words that merely contain the new tokens still evaluate (valuation_method,
  # executed_amount, connection_fee are column-like names; \b keeps them apart)
  @security
  Scenario: C1-H Ordinary formulas still pass the denylist
    Then the OWASP formula guard accepts:
      | formula                                                        |
      | capital_commitment.committed_amount_cents * 0.02               |
      | fund.valuation_method == "NAV" ? 1 : 0                         |
      | @executed_amount_cents.to_d / 100                              |
      | capital_commitment.custom_fields.connection_fee.to_d           |

  ##############################################################################
  # C2 — Calculation fields named by id
  ##############################################################################

  # C2-1 — Error case: a company admin names an existing Calculation field by id and leaves field_type out
  @security
  Scenario: C2-1 An existing Calculation field cannot be changed by id alone
    Given there is a user "first_name=Asha" for an entity "name=Calc Firm;entity_type=Investment Fund"
    And the entity has an "Investor" form type with a Calculation field "irr_calc"
    Then a non-support user may not submit the Calculation field by id without its type

  # C2-H — Happy path: the same user saving the form's other fields (the editor never renders Calculation
  # fields for them) is unaffected, and support may change the Calculation field
  @security
  Scenario: C2-H Other fields still save, and support may change Calculation fields
    Given there is a user "first_name=Asha" for an entity "name=Calc Firm;entity_type=Investment Fund"
    And the entity has an "Investor" form type with a Calculation field "irr_calc"
    Then a non-support user may submit the form type's other fields
    And a support user may submit the Calculation field by id

  ##############################################################################
  # C3 / H8 — import file names and zip symlinks
  ##############################################################################

  # C3-1 — Error case: a File Name cell that climbs out of the upload folder, or a symlink leading out, is refused
  @security
  Scenario: C3-1 Import file names cannot leave the upload folder
    Given an OWASP import upload folder with files "a.pdf, sub/q1.pdf" and a symlink "link.pdf" to a file outside it
    Then the import file path for these names is refused:
      | name                    |
      | ../secret.txt           |
      | ../../../../etc/passwd  |
      | link.pdf                |
      | sub/../../secret.txt    |

  # C3-H — Happy path and edge cases: names in the folder, in a zip sub-folder, any letter case, Office temp
  # names starting with "~", and an absolute-looking name (kept under the folder, as before) all still resolve
  @security
  Scenario: C3-H Real import file names still resolve
    Given an OWASP import upload folder with files "a.pdf, sub/q1.pdf" and a symlink "link.pdf" to a file outside it
    Then the import file path for these names stays inside the folder:
      | name            | exists |
      | a.pdf           | yes    |
      | A.PDF           | yes    |
      | sub/q1.pdf      | yes    |
      | sub/../a.pdf    | yes    |
      | missing.pdf     | no     |
      | ~$report.docx   | no     |
      | /etc/passwd     | no     |

  # H8-1 — Error case: after unzipping, a symlink leading outside is deleted; one pointing inside stays
  @security
  Scenario: H8-1 Symlinks leading out of an unzipped upload are removed
    Given an OWASP import upload folder with files "a.pdf, sub/q1.pdf" and a symlink "link.pdf" to a file outside it
    And the OWASP upload folder also has a symlink "inside.pdf" to "sub/q1.pdf"
    When the import removes escaping symlinks from the folder
    Then the OWASP upload folder has no "link.pdf"
    And the OWASP upload folder still has "inside.pdf" and "a.pdf"

  ##############################################################################
  # C4 / C5 — stored attribute paths (grid column keys, PDF password field, report exports)
  ##############################################################################

  # C4-1 — Error case: paths that hop to the class, write, or call Ruby internals are refused
  @security
  Scenario: C4-1 Attribute paths that reach the class or write are refused
    Then these attribute paths are refused:
      | path                    |
      | class.delete_all        |
      | class.last.PAN          |
      | investor.class.all      |
      | unscoped.first          |
      | fund.method             |
      | destroy                 |
      | capital_commitments.delete_all |
      | name!                   |
      | name=                   |
      | a b                     |

  # C4-H — Happy path: the shapes production uses still resolve, including custom fields named like methods
  @security
  Scenario: C4-H Production-shaped attribute paths still resolve
    Then these attribute paths are allowed:
      | path                                              |
      | investor_name                                     |
      | fund.name                                         |
      | valuation.per_share_value                         |
      | portfolio_company.custom_fields.hq_geography_founders |
      | investor_kyc.PAN                                  |
      | active?                                           |
      | investor.custom_fields.1_pan_attach               |
      | investor.custom_fields.update_only                |
      | investor.custom_fields.class                      |

  # C4-2 — Error case: reading "class.delete_all" on a real record deletes nothing and reads as blank
  @security
  Scenario: C4-2 A refused grid key deletes nothing
    Given there is a user "first_name=Ravi" for an entity "name=Grid Firm;entity_type=Investment Fund"
    And there are 2 OWASP investors for the entity
    When the grid cell "class.delete_all" is read for the first OWASP investor
    Then the grid cell value is blank
    And there are still 2 OWASP investors for the entity

  # C4-3 — Edge case: custom field values are read from json_fields, also when the name is also a method name
  @security
  Scenario: C4-3 Custom field keys read the stored value
    Given there is a user "first_name=Ravi" for an entity "name=Grid Firm;entity_type=Investment Fund"
    And there are 2 OWASP investors for the entity
    And the first OWASP investor has custom fields "sector=Fintech;class=A;update_only=yes"
    Then the grid cell "custom_fields.sector" for the first OWASP investor reads "Fintech"
    And the grid cell "custom_fields.class" for the first OWASP investor reads "A"
    And the grid cell "custom_fields.update_only" for the first OWASP investor reads "yes"
    And the grid cell "investor_name" for the first OWASP investor reads its name

  # C4-4 — Error case: a new grid column key that the reader would refuse is refused on save; an existing
  # column with an old key is not re-checked when something else changes
  @security
  Scenario: C4-4 Grid column keys are checked when they change
    Given there is a user "first_name=Ravi" for an entity "name=Grid Firm;entity_type=Investment Fund"
    And the entity has an "Investor" form type with a Calculation field "irr_calc"
    Then a grid column with key "class.delete_all" cannot be saved for the form type
    And a grid column with key "investor_name; text-col" can be saved for the form type
    And a grid column with key "portfolio_company.custom_fields.sector" can be saved for the form type
    # C4-5 — Edge case: report builder position rows keep saving; a malformed one is refused
    And a grid column with key "formula:formula_unpaid" can be saved for the form type
    And a grid column with key "pivot:capital_commitments" can be saved for the form type
    And a grid column with key "pivot:class.delete_all!" cannot be saved for the form type

  # C5-1 — Error case and happy path: the PDF password field accepts the production value and refuses an attack
  @security
  Scenario: C5-1 Custom notification PDF password field is an attribute path
    Given there is a user "first_name=Mira" for an entity "name=Notice Firm;entity_type=Investment Fund"
    Then a custom notification with PDF password field "class.delete_all" cannot be saved
    And a custom notification with PDF password field "investor_kyc.PAN" can be saved

  ##############################################################################
  # H1 — no secret keys in browser JavaScript
  ##############################################################################

  # H1-1 — Error case (drift guard): no OpenAI-style secret key in any JavaScript the app serves
  @security
  Scenario: H1-1 No API secret keys in app JavaScript
    Then no file under "app/javascript" contains an OpenAI secret key
    And no file under "vendor/javascript" contains an OpenAI secret key

  ##############################################################################
  # H3 — sub_domain in sign-in links
  ##############################################################################

  # H3-1 — Error case: a company admin cannot set a sub_domain that moves a sign-in link to another host
  @security
  Scenario: H3-1 A sub_domain that is not one DNS label is refused when changed
    Given there is a user "first_name=Kiran" for an entity "name=Sub Firm;entity_type=Investment Fund"
    Then the entity cannot change its sub_domain to:
      | sub_domain       |
      | evil.example?    |
      | evil.example     |
      | evil/x           |
      | a b              |

  # H3-2 — Edge case: an entity whose stored sub_domain predates the rule (395 investor entities in production,
  # e.g. "a.a.films-pvt-ltd466") still saves other changes, and sign-in links ignore that value
  @security
  Scenario: H3-2 Old unsafe sub_domains keep saving and are not used in sign-in links
    Given there is a user "first_name=Kiran" for an entity "name=Sub Firm;entity_type=Investment Fund"
    And the entity's sub_domain was stored as "a.a.films-pvt-ltd466" before the rule
    Then the entity can still save a new name "Sub Firm Renamed"
    And the entity's safe sub_domain is blank

  # H3-H — Happy path: ordinary sub_domains (letters, digits, hyphens, the two production ones with "_") pass
  @security
  Scenario: H3-H Ordinary sub_domains are accepted and used
    Given there is a user "first_name=Kiran" for an entity "name=Sub Firm;entity_type=Investment Fund"
    Then the entity can change its sub_domain to:
      | sub_domain    |
      | golden-angels |
      | fund2024      |
      | My-Fund       |
      | acme_capital  |

  ##############################################################################
  # H4 — PDF renderer asset host
  ##############################################################################

  # H4-1 — Error case and happy path: only our own hosts are trusted as the PDF asset host
  @security
  Scenario: H4-1 PDF asset host trusts only our own hosts
    Given the deployment host is "app.caphive.com" with base domain "caphive.com"
    Then the PDF asset host check gives:
      | host                    | trusted |
      | app.caphive.com         | yes     |
      | caphive.com             | yes     |
      | tenant1.caphive.com     | yes     |
      | evil.example            | no      |
      | caphive.com.evil.example | no     |
      | evilcaphive.com         | no      |

  ##############################################################################
  # H5 — KPI name in SQL
  ##############################################################################

  # H5-1 — Error case: a KPI name carrying SQL is a plain string to match, and the KPI falls back to a text field
  @security
  Scenario: H5-1 A KPI name with SQL in it is matched as text
    Given there is a user "first_name=Nila" for an entity "name=KPI Firm;entity_type=Company"
    And the entity has a KPI form type with a field "revenue" whose meta data is "sales,turnover"
    Then the KPI named "x%' and 1=1 and '%'='" uses a "TextField" custom field
    And the KPI named "Sales" uses the "revenue" custom field
    And the KPI named "sal_s" uses a "TextField" custom field

  ##############################################################################
  # H6 — document template merge fields
  ##############################################################################

  # H6-1 — Error case: template fields that hop to the class or drop a relation's scope render blank
  @security
  Scenario: H6-1 Template fields cannot reach other firms' records
    Given there is a user "first_name=Uma" for an entity "name=Template Firm;entity_type=Investment Fund"
    And there are 2 OWASP investors for the entity
    And another firm has 1 OWASP investor
    Then the template field "investor.class.name" renders blank
    And the template field "investor.entity.investors.unscoped.count" renders blank
    And the template field "investor.entity.investors.klass.count" renders blank
    And the template field "investor.entity.investors.count" renders "2"
    And the template field "investor.investor_name" renders the investor's name

  ##############################################################################
  # H7 — fund formula imports
  ##############################################################################

  # H7-1 — Error case: a firm user who may upload imports cannot upload fund formulas; support can; other import
  # types and editing an existing fund formula upload are unchanged
  @security
  Scenario: H7-1 Fund formula uploads are support-only
    Given there is a user "first_name=Dev" for an entity "name=Formula Firm;entity_type=Investment Fund"
    And there is a fund "name=Formula Fund" for the entity
    Then a "FundFormula" upload to the fund is refused for the user although other uploads would be allowed
    And a "CapitalCommitment" upload to the fund follows the usual import rule for the user
    And an existing "FundFormula" upload to the fund can still be edited under the usual import rule
    And a "FundFormula" upload to the fund follows the usual import rule for a support user

  ##############################################################################
  # M1 / M2 — logs and error emails
  ##############################################################################

  # M1-1 — Error case: upper-case PAN / IFSC keys (the real column names) and request credentials are filtered
  @security
  Scenario: M1-1 Upper-case PII keys and request credentials are filtered
    Then the log filter hides the values of:
      | key                    |
      | PAN                    |
      | Pan                    |
      | IFSC_code              |
      | HTTP_COOKIE            |
      | HTTP_AUTHORIZATION     |
      | rack.request.cookie_hash |
      | rack.session           |
      | signed_id              |

  # M1-2 — Edge case: look-alike keys stay visible (as L8-1, now case-insensitively)
  @security
  Scenario: M1-2 Look-alike keys stay visible
    Then the log filter keeps the values of:
      | key           |
      | company_name  |
      | SPAN          |
      | PAN_verified  |
      | HTTP_ACCEPT   |
      | HTTP_HOST     |

  ##############################################################################
  # N1 — Calculation fields through the custom field import
  ##############################################################################

  # N1-1 — Error case: a firm user's import may not add a Calculation field, change a stored one's Ruby, or turn a
  # stored one into another type
  @security
  Scenario: N1-1 A non-support custom field import cannot add or change Calculation fields
    Given there is a user "first_name=Asha" for an entity "name=Calc Firm;entity_type=Investment Fund"
    And the entity has an "Investor" form type with a Calculation field "irr_calc"
    And a custom field import of the form type uploaded by the user
    Then these custom field import rows are refused:
      | id        | name     | field_type  | metadata                      |
      |           | new_calc | Calculation | Rails.application.credentials |
      | calc      | irr_calc | Calculation | investor_name.to_s.upcase     |
      | calc      | irr_calc | TextField   |                               |

  # N1-H — Happy path: ordinary rows, a stored Calculation field repeated unchanged (an exported sheet re-imported),
  # and uploads by support (signed in as the client, or with the support role) are all accepted
  @security
  Scenario: N1-H Ordinary rows, unchanged Calculation rows and support uploads are accepted
    Given there is a user "first_name=Asha" for an entity "name=Calc Firm;entity_type=Investment Fund"
    And the entity has an "Investor" form type with a Calculation field "irr_calc"
    And a custom field import of the form type uploaded by the user
    Then these custom field import rows are accepted:
      | id        | name      | field_type  | metadata           |
      |           | nickname2 | TextField   |                    |
      | text      | nickname  | TextField   |                    |
      | calc      | irr_calc  | Calculation | investor_name.to_s |
    When the custom field import was uploaded by support signed in as the user
    Then these custom field import rows are accepted:
      | id        | name     | field_type  | metadata                  |
      |           | new_calc | Calculation | investor_name.to_s        |
      | calc      | irr_calc | Calculation | investor_name.to_s.upcase |

  # N1-2 — Edge case: the support user is recorded on the upload and cannot be posted by the client
  @security
  Scenario: N1-2 The support user on an upload comes from the session, never from the form
    Then the import upload form does not accept "support_user_id"
