@rack_test
Feature: A DR drill copy never contacts users, and the real app is untouched
  A drill rebuilds an environment from real backups and runs the real app on that copy. It must
  be invisible to users: no email, WhatsApp, SMS or push notification, and no timed job that
  would send one. Drill servers carry DR_DRILL_STACK (written only into a drill branch's .env),
  and only there does the app stop every outgoing channel at one choke point each: a mail
  interceptor, a guard on outgoing web requests to the messaging providers, and no timed jobs.
  The real app never has the flag, so none of this switches on for it.

  These scenarios exercise DrillStack's pieces directly; activating them process-wide would
  silence this test run. The next staging drill proves them on real servers.

  # H1 — Happy path: email on a drill copy is stopped and counted
  Scenario: The drill mail interceptor stops delivery
    Given an in-memory cache for the drill suppression count
    When the drill mail interceptor sees an email to "lp@example.com" titled "Capital call reminder"
    Then that email is not delivered
    And 1 outgoing message has been suppressed

  # H2 / H3 / H4 — Happy path: WhatsApp, push and SMS requests never leave a drill server
  Scenario Outline: A request to a messaging provider is answered locally on a drill copy
    Given an in-memory cache for the drill suppression count
    When a guarded request is sent to "<host>"
    Then it is answered locally with a 200 and no connection is made
    And 1 outgoing message has been suppressed

    Examples:
      | host                     |
      | live-server-1234.wati.io |
      | exp.host                 |
      | verify.twilio.com        |

  # E3 — Edge case: everything a drill itself needs still goes out
  Scenario Outline: Requests to other hosts pass through the guard
    When a guarded request is sent to "<host>"
    Then it is passed through to the real connection

    Examples:
      | host                           |
      | s3.ap-south-1.amazonaws.com    |
      | github.com                     |
      | api.twilio.com.evil.example    |

  # H5 — Happy path: no timed jobs on a drill copy
  Scenario: Timed jobs are not registered on a drill stack
    When timed-job registration is decided with DR_DRILL_STACK "ap-south-2"
    Then timed jobs are not registered

  # E1 / E2 — Edge case: the real app is untouched
  Scenario: Nothing switches on for the real app
    When the drill safeguards are activated without DR_DRILL_STACK
    Then nothing is switched on
    And timed-job registration is decided with DR_DRILL_STACK ""
    And timed jobs are registered

  # X1 — Error case: verification catches a live channel on a drill copy
  Scenario: A drill copy with live mail fails verification
    When drill silence is graded with mail interception "off", the request guard "on", 0 timed jobs and no crontab
    Then the drill silence grade is "fail" mentioning "mail delivery is live"

  # X2 — Error case: verification catches timed jobs on a drill copy
  Scenario: A drill copy with timed jobs fails verification
    When drill silence is graded with mail interception "on", the request guard "on", 3 timed jobs and no crontab
    Then the drill silence grade is "fail" mentioning "3 timed jobs registered"

  # H6 — Happy path: a silent drill passes and says how much it held back
  Scenario: A silent drill copy passes verification with its suppressed count
    When drill silence is graded with mail interception "on", the request guard "on", 0 timed jobs and no crontab
    Then the drill silence grade is "ok" mentioning "nothing can reach users"

  # S1 — Safeguard: the flag must never reach a real environment through a committed .env file
  Scenario: No committed environment file carries the drill flag
    When every committed .env file is read
    Then none of them sets DR_DRILL_STACK

  # S2 — Safeguard: a drill server announces itself loudly at boot
  Scenario: A drill server's boot message says all outgoing contact is suppressed
    When the drill boot message is built for region "ap-south-2"
    Then the drill boot message says "DRILL STACK (ap-south-2): all outgoing contact suppressed"

  # E4 — Edge case: the block form (Net::HTTP.post) reads the response through a block
  Scenario: A block-form request to a messaging provider still gets the local answer
    Given an in-memory cache for the drill suppression count
    When a guarded block-form request is sent to "live-server-1234.wati.io"
    Then the block received the local 200
    And 1 outgoing message has been suppressed

  # X3 — Error case: the verify check must read the REAL interceptor registry. The 14:39 drill's
  # check crashed (NameError: @@delivery_interceptors in Mail::Message) because only the grading
  # was tested, never the lookup.
  Scenario: Verification sees the mail interceptor exactly when it is registered
    Given the drill mail interceptor is not registered
    Then verification reports mail as not intercepted
    When the drill mail interceptor is registered with ActionMailer
    Then verification reports mail as intercepted
