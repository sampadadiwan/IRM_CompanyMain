/**
 * CapHive Gmail add-on.
 *
 * Host adapter only. Matching, dedup, authorization and persistence all live in Rails
 * behind /api/v1/mail/*, shared with the Outlook task pane, so an email filed from Gmail
 * and the same email filed from Outlook produce the same record.
 *
 * What changed from the previous version (docs/modules/mail_addins/mail_addin_review.md):
 *  - sign-in no longer collects the CapHive password in a plaintext CardService input;
 *    it opens a browser tab where the normal session (and therefore SSO/MFA) applies
 *  - the API host comes from a script property instead of being hardcoded to a dev server
 *  - To and CC are actually sent, rather than extracted and then replaced with empty arrays
 *  - manual record selection is restored, so an unmatched email can still be filed —
 *    previously the only option offered was "sign in as somebody else"
 *  - signing in no longer silently files the email before the user confirms the target
 *  - the RFC Message-ID is sent, making filing idempotent and comparable with Outlook
 *  - the body is sent as HTML, matching Outlook, instead of getPlainBody()
 *  - attachments are filed
 */

// ---------------------------------------------------------------- configuration

/**
 * Base URL of the CapHive instance this project talks to, e.g. https://app.caphive.com.
 *
 * Normally compiled in: `rake gmail:setup[<env>]` generates Config.gs from
 * config/gmail_addins.yml, so a freshly pushed project is already pointed at the right
 * host with no console step. Staging and production are separate Apps Script projects and
 * therefore separate constants, which is what makes it impossible for the staging add-on
 * to write to production.
 *
 * A Script Property still overrides it, so a deployed add-on can be repointed during an
 * incident without a push. Note the previous build had only the property, documented it,
 * and then ignored it in favour of a hardcoded dev hostname.
 */
function getApiUrl() {
  var override = PropertiesService.getScriptProperties().getProperty('CAPHIVE_API_URL');
  // typeof, not a bare reference: Config.gs is generated, and an un-built project would
  // otherwise fail with a ReferenceError instead of the explanation below.
  var compiledIn = (typeof CAPHIVE_API_URL === 'string') ? CAPHIVE_API_URL : null;
  var url = override || compiledIn;
  if (!url) {
    throw new Error(
      'No CapHive host configured. This project was pushed without Config.gs — ' +
      'run `rake gmail:setup[<env>]` from the IRM repo, or set CAPHIVE_API_URL under ' +
      'Project Settings > Script Properties.'
    );
  }
  return url.replace(/\/+$/, '');
}

function getAuthToken() {
  var props = PropertiesService.getUserProperties();
  var token = props.getProperty('CAPHIVE_TOKEN');
  var expiresAt = props.getProperty('CAPHIVE_TOKEN_EXPIRES_AT');
  if (!token) return null;
  // Treat an expired token as absent, so the user gets a sign-in card rather than a 401.
  if (expiresAt && new Date(expiresAt) <= new Date()) return null;
  return token;
}

function clearAuthToken() {
  var props = PropertiesService.getUserProperties();
  props.deleteProperty('CAPHIVE_TOKEN');
  props.deleteProperty('CAPHIVE_TOKEN_EXPIRES_AT');
}

// ---------------------------------------------------------------- brand

/**
 * CapHive palette, mirroring the website's :root custom properties
 * (public/website/assets/css/caphive.css). CardService takes hex strings only — it has no
 * notion of a stylesheet — so these are the single source of truth for the add-on.
 */
var BRAND = {
  orange: '#FF4D00',   // --orange, primary action
  ink:    '#101010',   // --fg
  muted:  '#6F6A62',   // --mut
  filed:  '#A33100',   // already-filed notices, a readable tint of the brand orange
  ok:     '#067A5B',
  warn:   '#8A5A00',
  error:  '#B3261E'
};

// ---------------------------------------------------------------- entry points

/**
 * Contextual trigger: fires when the user opens a message.
 */
function onGmailMessageOpen(e) {
  try {
    if (!getAuthToken()) return buildSignInCard();

    var email = extractEmailData(e);
    var match = apiPost('/api/v1/mail/match', {
      from_email: email.fromEmail,
      to_emails: email.toEmails,
      cc_emails: email.ccEmails,
      mailbox_email: email.mailboxEmail,
      internet_message_id: email.internetMessageId
    });

    return buildMatchCard(email, match);
  } catch (error) {
    if (String(error.message) === 'unauthorized') return buildSignInCard();
    return buildErrorCard(error.message);
  }
}

/**
 * Homepage trigger: shown when the add-on is opened without a message selected.
 */
function onHomepage() {
  if (!getAuthToken()) return buildSignInCard();
  return buildSimpleCard('CapHive', 'Open an email to file it to CapHive.');
}

// ---------------------------------------------------------------- message data

function extractEmailData(e) {
  // Scoped to the message the user is looking at. The add-on requests only
  // gmail.addons.current.message.readonly, not full-mailbox gmail.readonly, so this token
  // must be set before touching GmailApp — the previous build's action handlers skipped
  // this and only worked because they held the broader restricted scope.
  GmailApp.setCurrentMessageAccessToken(e.gmail.accessToken);
  var message = GmailApp.getMessageById(e.gmail.messageId);
  return emailDataFrom(message, e.gmail.messageId);
}

/**
 * Re-reads a message inside an action handler, where the event carries the access token
 * in e.gmail.accessToken just as the trigger event does.
 */
function extractEmailDataFromAction(e) {
  GmailApp.setCurrentMessageAccessToken(e.gmail.accessToken);
  var message = GmailApp.getMessageById(e.gmail.messageId);
  return emailDataFrom(message, e.gmail.messageId);
}

function emailDataFrom(message, gmailMessageId) {
  return {
    gmailMessageId: gmailMessageId,
    // The stable RFC 5322 Message-ID. The previous build sent Gmail's own account-specific
    // id instead, so the same email filed from Gmail and Outlook produced unrelated rows.
    internetMessageId: message.getHeader('Message-ID'),
    subject: message.getSubject() || '(no subject)',
    // HTML, matching what the Outlook pane sends. getPlainBody() discarded all formatting,
    // tables and links.
    body: message.getBody(),
    fromEmail: extractAddress(message.getFrom()),
    toEmails: extractAddresses(message.getTo()),
    ccEmails: extractAddresses(message.getCc()),
    // Address of the mailbox being read. The server excludes it from matching: the user is
    // a recipient of everything in their own inbox, so an investor record registered
    // against this address would match every email they open.
    mailboxEmail: mailboxAddress(),
    receivedAt: message.getDate().toISOString(),
    attachments: message.getAttachments({ includeInlineImages: false, includeAttachments: true })
  };
}

/** "Name <a@b.com>" -> "a@b.com" */
function extractAddress(value) {
  if (!value) return '';
  var match = String(value).match(/<(.+?)>/);
  return (match ? match[1] : String(value)).toLowerCase().trim();
}

function extractAddresses(value) {
  if (!value) return [];
  return String(value).split(',').map(extractAddress).filter(function (a) { return a; });
}

// ---------------------------------------------------------------- api

function apiRequest(path, options) {
  var token = getAuthToken();
  if (!token) throw new Error('unauthorized');

  options = options || {};
  options.headers = { Authorization: 'Bearer ' + token, Accept: 'application/json' };
  options.muteHttpExceptions = true;

  var response = UrlFetchApp.fetch(getApiUrl() + path, options);
  var code = response.getResponseCode();

  if (code === 401) {
    clearAuthToken();
    throw new Error('unauthorized');
  }

  var body = response.getContentText();
  var parsed;
  try {
    parsed = JSON.parse(body);
  } catch (e) {
    throw new Error('CapHive returned an unreadable response (HTTP ' + code + ').');
  }

  if (code >= 400) {
    throw new Error(parsed.errors ? parsed.errors.join(', ') : 'CapHive returned HTTP ' + code + '.');
  }
  return parsed;
}

function apiPost(path, payload) {
  return apiRequest(path, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload)
  });
}

function apiGet(path) {
  return apiRequest(path, { method: 'get' });
}

// ---------------------------------------------------------------- cards

function buildSignInCard() {
  var card = CardService.newCardBuilder().setHeader(cardHeader());
  var section = CardService.newCardSection();

  section.addWidget(CardService.newTextParagraph().setText(
    'Sign in to CapHive to file emails. Sign-in opens in a browser tab so your ' +
    'organisation&rsquo;s usual login — including single sign-on — applies.'
  ));

  // ScriptApp's state token lets Google route the browser tab's redirect back into this
  // script, so no password is ever typed into a card.
  var state = ScriptApp.newStateToken().withMethod('authCallback').withTimeout(3600).createToken();
  var signInUrl = getApiUrl() + '/gmail_addin/oauth_start?redirect_uri=' +
    encodeURIComponent(getCallbackUrl() + '?state=' + state);

  section.addWidget(CardService.newTextButton()
    .setText('Sign in to CapHive')
    .setBackgroundColor(BRAND.orange)
    .setOpenLink(CardService.newOpenLink()
      .setUrl(signInUrl)
      .setOpenAs(CardService.OpenAs.FULL_SIZE)
      .setOnClose(CardService.OnClose.RELOAD_ADD_ON)));

  card.addSection(section);
  return card.build();
}

function buildMatchCard(email, match) {
  var card = CardService.newCardBuilder().setHeader(cardHeader());
  var section = CardService.newCardSection();

  section.addWidget(CardService.newKeyValue()
    .setTopLabel('Email')
    .setContent(email.subject)
    .setMultiline(true));

  // Already-filed takes priority: the useful answer is "this is already in CapHive",
  // not a fresh guess at who it belongs to.
  if (match.filed && match.filed.filed) {
    var filedBy = match.filed.filed_by ? ' by ' + match.filed.filed_by : '';
    section.addWidget(CardService.newTextParagraph().setText(
      '<font color="' + BRAND.filed + '">Already filed' + filedBy + ' against ' +
      escapeHtml(match.filed.owner_name) + '.</font>'
    ));
    if (match.filed.url) {
      section.addWidget(CardService.newTextButton()
        .setText('View in CapHive')
        .setOpenLink(CardService.newOpenLink().setUrl(match.filed.url)));
    }
    card.addSection(section);
    card.addSection(buildPickerSection(email, match.candidates, 'File against a different record', true));
    return card.build();
  }

  var candidates = match.candidates || [];

  if (match.match_type === 'single') {
    var candidate = candidates[0];
    section.addWidget(CardService.newKeyValue()
      .setTopLabel('Filing against')
      .setContent(candidate.name)
      .setBottomLabel(reasonLabel(candidate.reason))
      .setIcon(CardService.Icon.PERSON));

    section.addWidget(CardService.newTextButton()
      .setText('File to CapHive')
      .setBackgroundColor(BRAND.orange)
      .setOnClickAction(CardService.newAction()
        .setFunctionName('onFileEmail')
        .setParameters({ ownerId: String(candidate.id), ownerName: candidate.name })));

    card.addSection(section);
    card.addSection(buildPickerSection(email, candidates, 'File against a different record', true));
    return card.build();
  }

  if (match.searchQuery) {
    // Re-rendered after a manual search. Without this branch the card kept asserting
    // "No matching record found" directly above the results the search had just returned,
    // and an empty result set was indistinguishable from not having searched at all.
    section.addWidget(CardService.newTextParagraph().setText(
      candidates.length
        ? candidates.length + ' record' + (candidates.length === 1 ? '' : 's') +
          ' matching &ldquo;' + escapeHtml(match.searchQuery) + '&rdquo;.'
        : '<font color="' + BRAND.warn + '">No records match &ldquo;' +
          escapeHtml(match.searchQuery) + '&rdquo;. Try a different search.</font>'
    ));
  } else if (match.match_type === 'multiple') {
    section.addWidget(CardService.newTextParagraph()
      .setText('<font color="' + BRAND.warn + '">More than one record matches this email.</font>'));
  } else {
    section.addWidget(CardService.newTextParagraph()
      .setText('<font color="' + BRAND.warn + '">No matching record found. Search for one below.</font>'));
  }

  card.addSection(section);
  card.addSection(buildPickerSection(email, candidates, 'Choose a record', false));
  return card.build();
}

/**
 * Manual selection. The previous build removed this entirely, so an email that did not
 * match — the common case, since matching is sender-only — simply could not be filed.
 *
 * @param collapsed [Boolean] whether to fold the section behind "Show more". Only true
 *   when the card already offers a primary action and this is the "actually, file it
 *   somewhere else" escape hatch.
 *
 *   It must be false whenever this section IS the card's purpose. A collapsible section
 *   shows only its first two widgets, which here are the search box and the Search button
 *   — so with no match found, search results and the File button rendered into a folded
 *   section and the user had to press "Show more" to see results they had just asked for.
 */
function buildPickerSection(email, candidates, title, collapsed) {
  var section = CardService.newCardSection().setHeader(title);

  if (collapsed) {
    // Explicit rather than relying on CardService's default of 2, so the two widgets kept
    // visible are a stated choice: the search box and its button.
    section.setCollapsible(true).setNumUncollapsibleWidgets(2);
  }

  section.addWidget(CardService.newTextInput()
    .setFieldName('owner_query')
    .setTitle('Search records')
    .setHint('Type a name, then Search'));

  section.addWidget(CardService.newTextButton()
    .setText('Search')
    .setOnClickAction(CardService.newAction().setFunctionName('onSearchOwners')));

  if (candidates && candidates.length) {
    var dropdown = CardService.newSelectionInput()
      .setType(CardService.SelectionInputType.DROPDOWN)
      .setTitle('Record')
      .setFieldName('selected_owner_id');

    for (var i = 0; i < candidates.length; i++) {
      dropdown.addItem(candidates[i].name, String(candidates[i].id), i === 0);
    }
    section.addWidget(dropdown);

    section.addWidget(CardService.newTextButton()
      .setText('File to selected record')
      .setBackgroundColor(BRAND.orange)
      .setOnClickAction(CardService.newAction().setFunctionName('onFileEmailSelected')));
  }

  return section;
}

function buildSuccessCard(ownerName, filingUrl, filingId, alreadyFiled) {
  var card = CardService.newCardBuilder().setHeader(cardHeader());
  var section = CardService.newCardSection();

  section.addWidget(CardService.newTextParagraph().setText(
    alreadyFiled
      ? '<font color="' + BRAND.filed + '">Already filed against ' + escapeHtml(ownerName) + '.</font>'
      : '<font color="' + BRAND.ok + '">Filed to ' + escapeHtml(ownerName) + '.</font>'
  ));

  if (filingUrl) {
    section.addWidget(CardService.newTextButton()
      .setText('View in CapHive')
      .setOpenLink(CardService.newOpenLink().setUrl(filingUrl)));
  }

  // Undo, because the most common mistake is filing against the wrong record.
  if (!alreadyFiled && filingId) {
    section.addWidget(CardService.newTextButton()
      .setText('Undo')
      .setOnClickAction(CardService.newAction()
        .setFunctionName('onUndoFiling')
        .setParameters({ filingId: String(filingId) })));
  }

  card.addSection(section);
  return card.build();
}

function buildErrorCard(message) {
  return buildSimpleCard('CapHive', '<font color="' + BRAND.error + '">' + escapeHtml(message) + '</font>');
}

function buildSimpleCard(title, html) {
  var card = CardService.newCardBuilder().setHeader(cardHeader());
  card.addSection(CardService.newCardSection().addWidget(
    CardService.newTextParagraph().setText(html)
  ));
  return card.build();
}

function cardHeader() {
  // Staging and production are two add-ons sitting side by side in the same Gmail side
  // panel. Naming the environment in the header is what stops a test email being filed
  // into production because the wrong icon was clicked.
  var label = (typeof CAPHIVE_ENV_LABEL === 'string' && CAPHIVE_ENV_LABEL) ? ' (' + CAPHIVE_ENV_LABEL + ')' : '';
  var header = CardService.newCardHeader().setTitle('CapHive Filing' + label);

  // The CapHive mark, served by the same host this build files into — so the staging
  // add-on shows staging's asset and a misconfigured host is visible rather than silent.
  // Wrapped because setImageUrl throws on a malformed URL, and a missing logo must never
  // cost the user the whole card.
  try {
    header.setImageUrl(getApiUrl() + '/manifests/icons/caphive-128.png')
          .setImageStyle(CardService.ImageStyle.SQUARE)
          .setImageAltText('CapHive');
  } catch (e) {
    // Header renders without the mark.
  }

  return header;
}

function reasonLabel(reason) {
  if (reason === 'contact') return 'Matched on a known investor contact';
  if (reason === 'primary_email') return 'Matched on the investor’s primary email';
  if (reason === 'domain') return 'Matched on email domain';
  return '';
}

/**
 * TextParagraph accepts only a small HTML subset, so an unescaped '<' from a record name
 * or a server error page corrupts the card. The previous build interpolated raw exception
 * text, including HTML error bodies, straight in.
 */
function escapeHtml(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// ---------------------------------------------------------------- actions

/**
 * Receives the token from the browser sign-in tab via Apps Script's usercallback.
 */
function authCallback(request) {
  var token = request.parameter.token;
  if (!token) {
    return HtmlService.createHtmlOutput('Sign-in failed. You can close this tab and try again.');
  }

  var props = PropertiesService.getUserProperties();
  props.setProperty('CAPHIVE_TOKEN', token);
  if (request.parameter.expires_at) {
    props.setProperty('CAPHIVE_TOKEN_EXPIRES_AT', request.parameter.expires_at);
  }

  return HtmlService.createHtmlOutput('Signed in to CapHive. You can close this tab.');
}

function onFileEmail(e) {
  return fileAndRespond(e, e.parameters.ownerId, e.parameters.ownerName);
}

function onFileEmailSelected(e) {
  var inputs = e.formInputs || {};
  var ownerId = inputs.selected_owner_id && inputs.selected_owner_id[0];
  if (!ownerId) return notify('Choose a record first.');
  return fileAndRespond(e, ownerId, null);
}

function onSearchOwners(e) {
  try {
    var inputs = e.formInputs || {};
    var query = (inputs.owner_query && inputs.owner_query[0]) || '';
    if (query.trim().length < 2) return notify('Type at least two characters to search.');

    var email = extractEmailDataFromAction(e);
    var results = apiGet('/api/v1/mail/owners?q=' + encodeURIComponent(query));

    return CardService.newActionResponseBuilder()
      .setNavigation(CardService.newNavigation().updateCard(
        buildMatchCard(email, {
          match_type: 'none',
          candidates: results.owners || [],
          filed: { filed: false },
          // Marks this as a search result set rather than the initial no-match state.
          searchQuery: query
        })
      ))
      .build();
  } catch (error) {
    if (String(error.message) === 'unauthorized') return reloadToSignIn();
    return notify(error.message);
  }
}

function fileAndRespond(e, ownerId, ownerName) {
  try {
    var email = extractEmailDataFromAction(e);

    var result = apiPost('/api/v1/mail/filings', {
      owner_id: ownerId,
      subject: email.subject,
      body: email.body,
      from: email.fromEmail,
      to: email.toEmails,
      cc_emails: email.ccEmails,
      message_id: email.gmailMessageId,
      internet_message_id: email.internetMessageId,
      received_at: email.receivedAt
    });

    uploadAttachments(result.id, email.attachments);

    return CardService.newActionResponseBuilder()
      .setNavigation(CardService.newNavigation().updateCard(
        buildSuccessCard(ownerName || 'the selected record', result.url, result.id, result.already_filed)
      ))
      .setNotification(CardService.newNotification().setText(
        result.already_filed ? 'This email was already filed.' : 'Filed to CapHive.'
      ))
      .build();
  } catch (error) {
    if (String(error.message) === 'unauthorized') return reloadToSignIn();
    return notify(error.message);
  }
}

/**
 * Attachments are posted separately as multipart, since the filing payload itself is JSON.
 * A failure here must not undo a successful filing, so it degrades to a notification.
 */
function uploadAttachments(filingId, attachments) {
  if (!filingId || !attachments || !attachments.length) return;

  var payload = {};
  for (var i = 0; i < attachments.length; i++) {
    payload['attachments[]'] = attachments[i].copyBlob().setName(attachments[i].getName());
    try {
      apiRequest('/api/v1/mail/filings/' + filingId + '/attachments', {
        method: 'post',
        payload: payload
      });
    } catch (error) {
      console.warn('Attachment upload failed: ' + error.message);
    }
  }
}

function onUndoFiling(e) {
  try {
    apiRequest('/api/v1/mail/filings/' + e.parameters.filingId, { method: 'delete' });
    return CardService.newActionResponseBuilder()
      .setNavigation(CardService.newNavigation().updateCard(
        buildSimpleCard('CapHive', 'Filing removed.')
      ))
      .setNotification(CardService.newNotification().setText('Filing removed.'))
      .build();
  } catch (error) {
    if (String(error.message) === 'unauthorized') return reloadToSignIn();
    return notify(error.message);
  }
}

function reloadToSignIn() {
  return CardService.newActionResponseBuilder()
    .setNavigation(CardService.newNavigation().updateCard(buildSignInCard()))
    .setNotification(CardService.newNotification().setText('Please sign in to CapHive again.'))
    .build();
}

function notify(message) {
  return CardService.newActionResponseBuilder()
    .setNotification(CardService.newNotification().setText(message))
    .build();
}

/** Apps Script's own callback endpoint for this script. */
/**
 * Address of the mailbox the add-on is running in.
 *
 * getActiveUser() is the user the add-on is acting for; getEffectiveUser() is a fallback
 * for contexts where the active user is withheld. Either can return an empty string, so
 * this returns null rather than '' and the server treats a missing value as "exclude
 * nothing" — a degraded match is acceptable, an exception on every message open is not.
 */
function mailboxAddress() {
  try {
    var email = Session.getActiveUser().getEmail() || Session.getEffectiveUser().getEmail();
    return email || null;
  } catch (e) {
    return null;
  }
}

function getCallbackUrl() {
  return 'https://script.google.com/macros/d/' + ScriptApp.getScriptId() + '/usercallback';
}
