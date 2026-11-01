Feature: The Gmail add-on sign-in hands a token only to this environment's own add-on
  The Gmail add-on opens /gmail_addin/oauth_start in a browser tab and receives a 30-day mail
  add-in token back through Apps Script's usercallback. It used to mint that token on the GET for
  ANY https://script.google.com URL containing "/usercallback", so a link to an attacker's own
  Apps Script project, clicked by a signed-in user, gave the attacker the user's token. Now the
  callback must be exactly /macros/d/<script id>/usercallback?state=... with a script id from
  this environment's credentials, the GET only shows a confirm page, and the token is minted by
  that page's POST. Mail add-in tokens are also refused at /mcp.
  Design: docs/security/security_review_2026_10.md, "H12 — Gmail add-in sign-in".

  Background:
    Given there is a user "first_name=Gmail-User" for an entity "entity_type=Investment Fund;name=Acme Mail;currency=INR"
    And the Gmail add-on script ids for this environment are "AKfycbPublishedAddon1,AKfycbPublishedAddon2"

  # H12-H — Happy path: the published add-on's callback, then the user confirms; the token goes back to that callback
  Scenario: The published add-on signs in after the user confirms
    When I open the Gmail add-on sign-in for script "AKfycbPublishedAddon2" with a state token
    Then I should see the Gmail add-on confirm page for the user
    When I confirm the Gmail add-on connection
    Then I should be redirected to the Gmail add-on callback for script "AKfycbPublishedAddon2" with a token
    And the token in the callback should be a mail add-in token for the user

  # H12-1 — Error case: an Apps Script project that is not this environment's add-on (anyone can publish one) gets nothing, on the GET or a forged POST
  Scenario: A script id that is not on this environment's list is refused
    When I open the Gmail add-on sign-in for script "AKfycbSomeoneElsesScript" with a state token
    Then the Gmail add-on sign-in should be refused with 400
    When I post the Gmail add-on confirmation for script "AKfycbSomeoneElsesScript"
    Then the Gmail add-on sign-in should be refused with 400
    And no mail add-in token should have been issued

  # H12-2 — Error case: an allowlisted id inside an altered callback (extra path, other host, other scheme, extra query, no state) is refused
  Scenario Outline: An altered callback address is refused
    When I open the Gmail add-on sign-in with the callback "<callback>"
    Then the Gmail add-on sign-in should be refused with 400
    And no mail add-in token should have been issued

    Examples:
      | callback                                                                                    |
      | https://script.google.com/macros/d/AKfycbPublishedAddon1/usercallback/extra?state=abc       |
      | https://script.google.com/evil/macros/d/AKfycbPublishedAddon1/usercallback?state=abc        |
      | https://script.google.com/macros/s/AKfycbPublishedAddon1/usercallback?state=abc             |
      | https://script.google.com.evil.test/macros/d/AKfycbPublishedAddon1/usercallback?state=abc   |
      | http://script.google.com/macros/d/AKfycbPublishedAddon1/usercallback?state=abc              |
      | https://script.google.com:8443/macros/d/AKfycbPublishedAddon1/usercallback?state=abc        |
      | https://script.google.com/macros/d/AKfycbPublishedAddon1/usercallback?state=abc&next=x      |
      | https://script.google.com/macros/d/AKfycbPublishedAddon1/usercallback?state=                |
      | https://script.google.com/macros/d/AKfycbPublishedAddon1/usercallback                       |
      | https://script.google.com/macros/d/AKfycbPublishedAddon1/usercallback?state=abc#frag        |

  # H12-3 — Edge case: a valid callback opened by a link alone (GET, no confirm) shows the confirm page and mints nothing
  Scenario: Opening the sign-in link does not issue a token on its own
    When I open the Gmail add-on sign-in for script "AKfycbPublishedAddon1" with a state token
    Then I should see the Gmail add-on confirm page for the user
    And no mail add-in token should have been issued

  # H12-X — Error case: a mail add-in token presented to /mcp is refused with 401, even where MCP is enabled
  Scenario: A mail add-in token cannot be used on the MCP endpoint
    Given the user's entity has MCP enabled
    And the user's MCP access token is a mail add-in token
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 401
