@entry_explanation
Feature: Reading what a formula depends on
  FormulaReferenceScanner reads a fund formula's text — never evaluating it — and reports the
  other entries it reads, the engine inputs it uses, and whether each is added or taken away.
  It is what lets the entry page's "How this was worked out" card and the report's Dependencies
  tab follow one number to the numbers it was built from.

  Scenario Outline: What a formula says it depends on
    When the formula "<formula>" is read
    Then its "<kind>" should be "<expected>"

    Examples:
      | formula                                                                             | kind          | expected        |
      | @a - @b                                                                             | fields        | a,b             |
      | @fund.id + @end_date.year                                                           | fields        |                 |
      | @fund.id + @end_date.year                                                           | inputs        | fund,end_date   |
      | capital_commitment.since_inception('Management Fees', nil, @start_date, @end_date)  | helper names  | Management Fees |
      | capital_commitment.quarterly(nil, 'Operating Cost', @start_date, @end_date)         | helper types  | Operating Cost  |
      | capital_commitment.year_to_date('Setup Fees', nil, @start_date, @end_date)          | helper names  | Setup Fees      |
      | capital_commitment.since_inception(chosen_name, nil, @start_date, @end_date)        | unresolved    | 1               |
      | capital_commitment.account_entries.where(name: 'Fees').sum(:amount_cents)           | name filters  | Fees            |

  Scenario: A formula that is no longer valid Ruby is reported, not raised
    When the formula "this is ((( not ruby" is read
    Then reading it should report that it could not be read
    And its "fields" should be ""
