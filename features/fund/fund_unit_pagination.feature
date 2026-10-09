Feature: Fund unit pagination
  The Fund Units list shows one page of units at a time, newest issue date first,
  keeps filters while paging, and the download still exports every unit.

Background:
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=Alpha;unit_types=A,B" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor

Scenario: H1 First page shows 25 units with a pager
  Given the fund has 30 fund units of type "A"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list
  Then I should see 25 fund unit rows
  And I should see the fund units pager text "1-25"
  And I should see the fund units pager text "62"
  And I should see exactly one fund units pager

Scenario: H2 Page links move between pages
  Given the fund has 30 fund units of type "A"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list
  And I click the fund units page link "2"
  Then I should see 25 fund unit rows
  And I should see the fund units pager text "26-50"

Scenario: H3 Filters apply before paging
  Given the fund has 30 fund units of type "A"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list with "q[unit_type_eq]=A"
  Then I should see 25 fund unit rows
  And I should see the fund units pager text "30"

Scenario: H4 Download is not paginated
  Given the fund has 30 fund units of type "A"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list
  Then the fund units download should contain 62 unit rows

Scenario: H5 Embedded fund units list pages in place
  Given the fund has 30 fund units of type "A"
  When I open the investor page with the fund units section
  Then I should see 25 fund unit rows
  When I click the fund units page link "2"
  Then I should see 5 fund unit rows
  And I should still be on the investor page

Scenario: H6 Units are listed by latest issue date first
  Given the fund has 3 fund units of type "A"
  When I open the fund units list
  Then I should see 3 fund unit rows
  And the fund units should be listed by latest issue date first

Scenario: E1 25 or fewer units show the count but no page links
  Given the fund has 10 fund units of type "A"
  When I open the fund units list
  Then I should see 10 fund unit rows
  And I should see the fund units pager text "Showing 10 of 10"
  And I should not see fund units page links

Scenario: E2 No units shows no pager
  When I open the fund units list
  Then I should see 0 fund unit rows
  And I should not see a fund units pager

Scenario: E3 Changing a filter returns to page 1
  Given the fund has 30 fund units of type "A"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list with "page=3"
  And I open the fund units list with "q[unit_type_eq]=A"
  Then I should see the fund units pager text "1-25"

Scenario: E4 Page links keep the filter
  Given the fund has 30 fund units of type "A"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list with "q[unit_type_eq]=A"
  And I click the fund units page link "2"
  Then I should see 5 fund unit rows
  And I should see the fund units pager text "26-30"

Scenario: X1 A page beyond the end shows the last page
  Given the fund has 30 fund units of type "A"
  When I open the fund units list with "page=9"
  Then I should see 5 fund unit rows
  And I should see the fund units pager text "26-30"

Scenario: H7 Search finds units on any page
  Given the fund has 62 fund units of type "A"
  Given the fund has an old fund unit with reason "Needle in haystack"
  When I open the fund units list
  And I search the fund units list for "Needle in haystack"
  Then I should see 1 fund unit rows
  And I should see only fund units with reason "Needle in haystack"

Scenario: H8 Sorting covers every page
  Given the fund has 62 fund units of type "A"
  Given the fund units have increasing quantities
  When I open the fund units list
  And I sort the fund units list by "Quantity"
  Then I should see 25 fund unit rows
  And the fund unit rows should be ordered by quantity ascending

Scenario: E5 Search with no match shows nothing
  Given the fund has 30 fund units of type "A"
  When I open the fund units list
  And I search the fund units list for "zzzzqqqq"
  Then I should see 0 fund unit rows
  And I should not see a fund units pager

Scenario: E6 Page links keep the search
  Given the fund has 30 fund units of type "A" with reason "Batch X"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list
  And I search the fund units list for "Batch X"
  Then I should see the fund units pager text "30"
  When I click the fund units page link "2"
  Then I should see 5 fund unit rows
  And I should see only fund units with reason "Batch X"

Scenario: E7 Sorting keeps the search
  Given the fund has 30 fund units of type "A" with reason "Batch X"
  Given the fund has 32 fund units of type "B"
  When I open the fund units list
  And I search the fund units list for "Batch X"
  And I click the fund units page link "2"
  And I sort the fund units list by "Quantity"
  Then I should see 25 fund unit rows
  And I should see only fund units with reason "Batch X"

Scenario: E8 Embedded list searches in place
  Given the fund has 30 fund units of type "A" with reason "Batch X"
  Given the fund has 5 fund units of type "B"
  When I open the investor page with the fund units section
  And I search the fund units section for "Batch X"
  Then I should see 25 fund unit rows
  And I should see only fund units with reason "Batch X"
  And I should still be on the investor page


Scenario: E9 Import upload page pages its imported units
  Given the fund has 30 fund units of type "A"
  Given the fund units belong to an import upload
  When I open the import upload page
  Then I should see 25 fund unit rows
  And I should see the fund units pager text "1-25"
  When I click the fund units page link "2"
  Then I should see 5 fund unit rows
