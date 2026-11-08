@rack_test
Feature: A recovery proves what users do works, not only that each part is up
  The end-of-recovery checks gain five "does it work for a user" checks: through the load
  balancer (certificate, targets, database, sign-in page over HTTPS), document files present in
  S3, a background job runs, the sign-in page and a signed-in request work, and LibreOffice makes
  a PDF. Each is a way a stack could pass every other check and still be broken for users.
  These scenarios exercise Dr::ServingChecks' verdicts and the ping job; the checks themselves run
  on the recovered servers (dr:verify) and against the new load balancer (dr_edge_checks).

  # H1 / E1 / E2 / X1 — document files looked up in S3
  Scenario Outline: Document files present
    When <checked> document files are looked up and <missing> are missing
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | checked | missing | status | text                            |
      | 30      | 0       | ok     | 30 of 30 files found            |
      | 30      | 1       | warn   | may still be replicating        |
      | 30      | 5       | fail   | documents will not open         |
      | 0       | 0       | warn   | no stored documents to check    |

  # H2 / X2 — a background job runs
  Scenario Outline: A queued job must run
    When the queued job ran after "<seconds>" seconds
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | seconds | status | text                              |
      | 4.2     | ok     | ran in 4.2s                       |
      | never   | fail   | would not be processed            |

  # H3 / X3 / X4 — the sign-in page
  Scenario Outline: The sign-in page renders with its form
    When the sign-in page answers HTTP "<code>" with '<body>'
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | code | body                                    | status | text                    |
      | 200  | <input name="user[password]">           | ok     | with the sign-in form   |
      | 200  | Back soon, maintenance                      | fail   | no sign-in form         |
      | 502  | Bad Gateway                             | fail   | does not load           |

  # H4 / X5 / X6 — a signed-in request (drill copies only)
  Scenario Outline: A signed-in API read returns JSON
    When the signed-in read answers HTTP "<code>" with '<body>'
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | code | body             | status | text                        |
      | 200  | [{"id":1}]       | ok     | HTTP 200 with JSON          |
      | 200  | <html>oops</html> | fail   | not JSON                    |
      | 401  | {}               | fail   | signed-in requests fail     |

  # H5 / X7 / X8 / X9 — LibreOffice makes a PDF
  Scenario Outline: A Word file converts to PDF
    When the PDF conversion produced "<head>" with error "<error>"
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | head     | error                 | status | text                          |
      | %PDF-1.7 |                       | ok     | converted to PDF              |
      | none     |                       | fail   | produced no PDF               |
      | PK\x03   |                       | fail   | not a PDF                     |
      | none     | Errno::ENOENT soffice | fail   | could not convert             |

  # H6 / X10 / X11 — the certificate, pinned to the load balancer
  Scenario Outline: The load balancer's certificate must be valid for the app host
    When curl to the app host through the load balancer exits <exit>
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | exit | status | text                         |
      | 0    | ok     | certificate valid for        |
      | 60   | fail   | browsers would refuse        |
      | 7    | fail   | could not connect over HTTPS |

  # H7 / X12 / X13 — target health
  Scenario Outline: Every app server must be healthy in the load balancer
    When <healthy> of <total> load balancer targets are healthy
    Then the serving check is "<status>" mentioning "<text>"

    Examples:
      | healthy | total | status | text                    |
      | 2       | 2     | ok     | 2 of 2 app servers      |
      | 1       | 2     | fail   | only to the healthy     |
      | 0       | 0     | fail   | no app servers          |

  # E3 — the sample covers older documents, not just the newest
  Scenario: Older documents are sampled across the id range
    When older document ids are picked below 110
    Then the ids are 10, 20, 30, 40, 50, 60, 70, 80, 90 and 100

  # H8 — the ping job leaves the token dr:verify waits for
  Scenario: The ping job records its token
    When the ping job runs with token "abc123"
    Then the cache holds the ping for "abc123"
