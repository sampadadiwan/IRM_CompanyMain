Feature: Text one user types is never run as script in another user's browser
  WHY THIS FEATURE EXISTS
  The October 2026 security review only covered cross-site scripting (XSS) for two places: CI
  widgets (L13, ci_widget_embeds.feature) and AI portfolio report sections (C3-7). A coverage review
  on 2026-11-05 found the same bug class live elsewhere. About 55 views print text that users typed
  with `.html_safe`, and the flash banner (layouts/_alerts.html.erb) prints every notice with
  `.html_safe`, including the 51 notices that interpolate a record's name.

  Nothing in the browser stops it either: the Content-Security-Policy is report-only
  (config/initializers/content_security_policy.rb sets content_security_policy_report_only = true)
  while it is rolled out, so injected script runs.

  Each scenario below is one real path where a lower-trust user's text reaches a different user's
  page:
    * GP employee  -> LP              (remittance notes, KYC form help text)
    * employee     -> company admin   (distribution notes, fund details, notification body)
    * any user     -> company admin   (their own name, echoed in a flash notice)
    * a link       -> whoever clicks  (a `return_to=javascript:...` Cancel link)

  THESE SCENARIOS FAIL TODAY, ON PURPOSE. They state the safe behaviour. Each comment names the
  view that has to change to make it pass. Fields typed in a rich-text editor (Trix) should keep
  their formatting, so the fix there is `sanitize`, not escaping. The bold check enforces that.

  # XSS-1 — Error case: a GP employee's remittance note is script in the LP's remittance page.
  #   Why: capital_remittances/show renders _show for every viewer, the LP included, and _show.html.erb
  #   prints `capital_remittance.notes.html_safe`. Notes is a plain textarea written by any employee
  #   with update rights on the call. A note like `<img src=x onerror=…>` runs in the LP's session.
  #   Fix: capital_remittances/_show.html.erb — drop .html_safe (plain text field).
  @security @rack_test
  Scenario: XSS-1 A remittance note runs no script on the LP's remittance page
    Given there is a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And there is an existing investor "investor_name=Kiran" with "1" users
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And the GP writes the XSS payload into the notes of the investor's remittance
    When I login as the investor user
    And I open the investor's remittance page
    Then the page shows the payload's text "Wire by Friday"
    And the page carries no injected script or event handler

  # XSS-2 — Error case: a company admin's custom-field help text is script on the LP's KYC form.
  #   Why: every form_custom_fields/_*.html.erb partial prints `field.help_text&.html_safe`. Help
  #   text is a plain text field set by the firm's company admin (FormTypePolicy#update?) and shown
  #   to every investor who fills the KYC form, here through the KYC magic link an LP receives by
  #   email. A GP admin's script would run in each LP's browser, on the app's own origin.
  #   Fix: form_custom_fields/_*.html.erb — sanitize (or escape) help_text.
  @security @rack_test
  Scenario: XSS-2 A custom field's help text runs no script on the LP's KYC form
    Given there is a user "first_name=FundAdmin" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=Kiran" with "1" users
    And there is a KYC for the investor with submission_status "link_sent"
    And the KYC's form has a custom field whose help text is the XSS payload
    When the investor opens their KYC form from the emailed signed link
    Then the page shows the payload's text "Wire by Friday"
    And the page carries no injected script or event handler

  # XSS-3 — Error case: an employee's distribution note is script in a colleague's or admin's session.
  #   Why: capital_distributions/show.html.erb prints `@capital_distribution.notes.html_safe`
  #   (Brakeman: High confidence). Notes come from a Trix editor, but the column stores whatever the
  #   request posts, so any employee with update rights on the distribution can save raw script.
  #   It then runs for the company admin who opens the distribution: privilege escalation in the firm.
  #   Fix: capital_distributions/show.html.erb — sanitize, keeping Trix formatting.
  @security @rack_test
  Scenario: XSS-3 A distribution note runs no script for the admin and keeps its formatting
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And there is a capital distribution "title=Q1 Distribution"
    And an employee writes the XSS payload into the distribution's notes
    When I open the distribution page
    Then the page shows the payload's text "Wire by Friday"
    And the payload's bold text is still bold
    And the page carries no injected script or event handler

  # XSS-4 — Error case: an employee's fund details are script on the fund page.
  #   Why: funds/_show2.html.erb prints `fund.details&.html_safe` on the fund page that every user of
  #   the firm opens. Any employee who may update the fund can store script in details.
  #   Fix: funds/_show2.html.erb (and the unused funds/_show.html.erb) — sanitize, keeping formatting.
  @security @rack_test
  Scenario: XSS-4 Fund details run no script on the fund page and keep their formatting
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And an employee writes the XSS payload into the fund's details
    When I open the fund page of "Artha Select"
    Then the page shows the payload's text "Wire by Friday"
    And the payload's bold text is still bold
    And the page carries no injected script or event handler

  # XSS-5 — Error case: an employee's notification template body is script on its show page.
  #   Why: custom_notifications/show.html.erb prints `@custom_notification.body.html_safe` (Brakeman:
  #   High). CustomNotificationPolicy#create? lets any employee with create rights on the fund write
  #   a template. Only is_erb templates are support-only, and this one is not ERB. The company admin
  #   who reviews the template before it goes to LPs runs the script.
  #   Fix: custom_notifications/show.html.erb — sanitize, keeping formatting (the body is rich text).
  @security @rack_test
  Scenario: XSS-5 A notification template body runs no script on its show page and keeps its formatting
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And an employee saves a notification template for the fund whose body is the XSS payload
    When I open that notification template
    Then the page shows the payload's text "Wire by Friday"
    And the payload's bold text is still bold
    And the page carries no injected script or event handler

  # XSS-6 — Error case: a user's own name, echoed in an admin's flash notice, is script.
  #   Why: layouts/_alerts.html.erb prints `notice.html_safe` and `alert.html_safe`, and 51 controller
  #   notices interpolate a record's name. Here UsersController#reset_two_factor says "Two-factor
  #   method reset for #{@user.full_name}". Every user can edit their own first name (only presence
  #   is validated), so a colleague or LP sets theirs to markup. Their script then runs in the company
  #   admin's session the moment the admin resets their 2FA.
  #   InvestorAdvisorsController#switch already escapes its name for this reason. Escaping in the
  #   partial fixes all 51 notices at once.
  #   Fix: layouts/_alerts.html.erb — escape (no flash message in the app relies on HTML).
  @security @rack_test
  Scenario: XSS-6 A colleague's name in a flash notice runs no script in the admin's session
    Given Im logged in as a user "first_name=Asha" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a colleague "first_name=Ravi;last_name=Kumar" in the same entity using WhatsApp two-factor
    And the colleague has set their first name to the XSS name payload
    When I reset the colleague's two-factor method
    Then the page shows the text "Two-factor method reset for"
    And the page carries no injected script or event handler

  # XSS-7 — Error case: a crafted link turns the Cancel button into script.
  #   Why: financial_statement_accounts/_form.html.erb and financial_statement_mapping_rules/_form.html.erb
  #   build Cancel as `link_to "Cancel", params[:return_to].presence || …` (Brakeman: High). Rails'
  #   link_to does not block `javascript:` URLs. A GP admin who opens a link from an email or chat and
  #   clicks Cancel runs the attacker's script in their own session.
  #   Fix: both forms — only accept a same-site path (e.g. through url_from / a leading "/" check).
  @security @rack_test
  Scenario Outline: XSS-7 A javascript: return_to never becomes the <form> Cancel link
    Given Alpha Fund I is set up for financial statements
    And I am signed in as the current user
    When I open the new <form> form with return_to "javascript:alert(document.cookie)"
    Then the Cancel link does not point at a javascript: URL

    Examples:
      | form                         |
      | financial statement account  |
      | financial statement mapping  |

  # XSS-7H — Happy path: a same-site return_to still drives the Cancel link (the feature it exists for).
  #   Why: the fix for XSS-7 must not break "Cancel returns to where I came from".
  @security @rack_test
  Scenario Outline: XSS-7H A same-site return_to is still the <form> Cancel link
    Given Alpha Fund I is set up for financial statements
    And I am signed in as the current user
    When I open the new <form> form with return_to "/funds"
    Then the Cancel link points at "/funds"

    Examples:
      | form                         |
      | financial statement account  |
      | financial statement mapping  |

  # XSS-8 — Error case: a record's name, interpolated into a card title, is script on its page.
  #   Why: the FormCard component (core/components/form_card.html.erb) printed `@title.html_safe`, and
  #   175 callers build the title from record names, e.g. documents/_form: "Document : #{document.name}".
  #   Anyone who can name a document (an LP uploading a KYC file, an employee) could plant script for
  #   every colleague who opens it. Fix: FormCard prints SafeHtml.ui_markup(@title), keeping the icons
  #   and tooltips callers pass on purpose and dropping handlers and scripts.
  @security @rack_test
  Scenario: XSS-8 A document's name in its card title runs no script on the document page
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true;enable_documents=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And a colleague uploads a document to the fund whose name is the XSS name payload
    When I open that document's edit page
    Then the page shows the text "Document :"
    And the page carries no injected script or event handler

  # XSS-9 — Error case: a JSON field's value in the audit trail is script for whoever reads the trail.
  #   Why: the audit trail draws any structured value (a custom field whose value is a Hash/Array, or a
  #   JSON column such as properties) through Json2table, and Json2table builds "<td>#{value}</td>"
  #   without escaping. The views marked its output html_safe, so a custom-field answer like
  #   `<img onerror=…>` ran for the company admin reviewing the audit trail. (Plain string values were
  #   already printed escaped.) Fix: safe_json_table (SafeHtml.json_table).
  @security @rack_test
  Scenario: XSS-9 A custom-field value in the audit trail runs no script and keeps its formatting
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And a colleague's change to the fund's custom fields put the XSS payload in the audit trail
    When I open the fund's audit trail
    Then the page shows the payload's text "Wire by Friday"
    And the payload's bold text is still bold
    And the page carries no injected script or event handler

  # XSS-10 — Error case: a sent email shown on the notification page is script on that page.
  #   Why: notifications/show printed the email's HTML with `.html_safe`. The email carries text other
  #   people wrote (a custom notification body, record names), and the page is shown to staff and,
  #   with ?debug=1, to the recipient LP. Fix: the email is shown in a sandboxed iframe (srcdoc, no
  #   allow-scripts) so it keeps its own styles but nothing in it can run.
  @security @rack_test
  Scenario: XSS-10 A sent email on the notification page is shown in a sandbox where nothing runs
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select;currency=INR" for the entity
    And a colleague received a notification whose sent email contains the XSS payload
    When I open that notification's page
    Then the page carries no injected script or event handler
    And the email is shown in a sandboxed frame that cannot run scripts
