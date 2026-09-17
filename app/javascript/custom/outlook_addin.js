/**
 * CapHive Outlook task pane.
 *
 * Host adapter only: it reads the selected message out of Office.js, renders the pane, and
 * talks to /api/v1/mail/*. All matching, dedup and persistence live in Rails, shared with
 * the Gmail add-on, so the same email filed from either client produces the same record.
 *
 * Behaviours this fixes over the previous version (docs/technical/mail_addin_review.md):
 *  - authenticates with a bearer token instead of a session cookie, which Outlook's
 *    cross-site iframe never sends
 *  - re-reads the message on ItemChanged, so the pane cannot file email A while the user
 *    is reading email B
 *  - sends internetMessageId, so filing is idempotent and works across Outlook and Gmail
 *  - sends To as well as From and CC, so sent mail can be matched
 *  - files attachments
 *  - tells the user when a message is already filed, and offers an undo
 */
(function () {
  'use strict';

  // Where the token lives between sessions. roamingSettings is per-user, per-add-in and
  // syncs across the user's Outlook clients.
  var TOKEN_KEY = 'caphive_token';
  var TOKEN_EXPIRY_KEY = 'caphive_token_expires_at';

  var state = {
    email: null,        // the message currently shown in the pane
    token: null,
    candidates: [],
    selectedOwnerId: null,
    filedState: null,   // { filed: true, id, url, ... } when already in CapHive
    lastFilingId: null  // set after a successful file, to support undo
  };

  // ---------------------------------------------------------------- boot

  // The one place that knows which host we are in. Everything below talks to `host`, so
  // the simulator exercises the real matching, filing, attachment and undo paths rather
  // than a parallel implementation — which is how the previous simulator drifted, having
  // its own copy of fileEmail that no longer matched the add-in's.
  var host = null;

  Office.onReady(function (info) {
    if (info.host === Office.HostType.Outlook) {
      host = OutlookHost();
    } else if (window.CAPHIVE_SIMULATOR) {
      host = SimulatorHost();
    } else {
      showError('This add-in only runs inside Outlook.');
      return;
    }

    state.token = host.readStoredToken();
    host.onItemChanged(loadCurrentItem);

    bindStaticHandlers();
    host.start(loadCurrentItem);
  });

  function bindStaticHandlers() {
    byId('sign-in-button').addEventListener('click', signIn);
    byId('file-button').addEventListener('click', fileEmail);
    byId('change-owner-button').addEventListener('click', toggleOwnerPicker);
    byId('owner-search').addEventListener('input', debounce(searchOwners, 250));
    byId('owner-select').addEventListener('change', onOwnerSelected);
    byId('undo-button').addEventListener('click', undoFiling);
  }

  // ---------------------------------------------------------------- item

  /**
   * Reads the currently selected message. Called on load and on every ItemChanged.
   */
  function loadCurrentItem() {
    resetForNewItem();

    state.email = host.readItem();
    // No reading pane, or a non-message item selected.
    if (!state.email) {
      showSection('empty');
      return;
    }

    byId('email-subject').textContent = state.email.subject;

    if (!state.token) {
      showSection('signed-out');
      return;
    }
    matchOwner();
  }

  function resetForNewItem() {
    state.candidates = [];
    state.selectedOwnerId = null;
    state.filedState = null;
    state.lastFilingId = null;
    clearMessages();
    byId('owner-picker').hidden = true;
    byId('undo-button').hidden = true;
    var fileButton = byId('file-button');
    fileButton.disabled = true;
    fileButton.textContent = 'File to CapHive';
    showSection('loading');
  }

  function addressOf(recipient) {
    return recipient && recipient.emailAddress ? recipient.emailAddress : null;
  }

  function addressesOf(recipients) {
    return (recipients || []).map(addressOf).filter(Boolean);
  }

  /**
   * Address of the mailbox currently open. Available under ReadItem — no extra permission.
   * Guarded because userProfile is absent in some hosts (and in the simulator), and a
   * missing mailbox address must degrade to "don't exclude anything", never to a crash.
   */
  function mailboxAddress() {
    try {
      return Office.context.mailbox.userProfile.emailAddress || null;
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------- hosts

  /** The real thing: reads Office.js and stores the token in roamingSettings. */
  function OutlookHost() {
    return {
      start: function (onReady) { onReady(); },

      // The pane stays open when the user selects a different message in Outlook on the
      // web and new Outlook. Without this the pane keeps showing — and files — the
      // message that was open when it was first launched.
      onItemChanged: function (handler) {
        if (!Office.context.mailbox.addHandlerAsync) return;
        Office.context.mailbox.addHandlerAsync(Office.EventType.ItemChanged, function () { handler(); });
      },

      readItem: function () {
        var item = Office.context.mailbox.item;
        if (!item) return null;

        return {
          subject: item.subject || '(no subject)',
          // item.from is absent on items in Drafts; item.sender is the read-mode field.
          from: addressOf(item.from) || addressOf(item.sender),
          to: addressesOf(item.to),
          cc: addressesOf(item.cc),
          // The stable RFC 5322 id. itemId is an EWS id — mailbox-specific, changes when
          // the item moves folder, and too long for the column it was written to.
          internetMessageId: item.internetMessageId,
          itemId: item.itemId,
          receivedAt: item.dateTimeCreated,
          // The address of the mailbox being read, which is on every message in it and so
          // carries no matching signal. Sent so the server can exclude it: it is normally a
          // different string from the CapHive login, and an investor registered against it
          // would otherwise match every email the user opens.
          mailboxEmail: mailboxAddress()
        };
      },

      getBody: function () {
        return new Promise(function (resolve, reject) {
          Office.context.mailbox.item.body.getAsync(Office.CoercionType.Html, function (result) {
            if (result.status === Office.AsyncResultStatus.Succeeded) resolve(result.value);
            else reject(new Error('Could not read the email body.'));
          });
        });
      },

      /**
       * Reads attachment content. Requires mailbox requirement set 1.8; hosts below that
       * file the message without attachments rather than failing outright.
       */
      getAttachments: function () {
        var item = Office.context.mailbox.item;
        if (!Office.context.requirements.isSetSupported('Mailbox', '1.8')) return Promise.resolve([]);
        if (!item.attachments || !item.attachments.length) return Promise.resolve([]);

        var wanted = item.attachments.filter(function (attachment) {
          // Inline images are part of the body, not documents worth filing.
          return !attachment.isInline &&
            attachment.attachmentType === Office.MailboxEnums.AttachmentType.File;
        });

        return Promise.all(wanted.map(function (attachment) {
          return new Promise(function (resolve) {
            item.getAttachmentContentAsync(attachment.id, function (result) {
              if (result.status === Office.AsyncResultStatus.Succeeded &&
                  result.value.format === Office.MailboxEnums.AttachmentContentFormat.Base64) {
                resolve({ name: attachment.name, blob: base64ToBlob(result.value.content) });
              } else {
                // One unreadable attachment should not block filing the email itself.
                resolve(null);
              }
            });
          });
        })).then(function (results) { return results.filter(Boolean); });
      },

      readStoredToken: function () {
        var settings = Office.context.roamingSettings;
        var token = settings.get(TOKEN_KEY);
        var expiresAt = settings.get(TOKEN_EXPIRY_KEY);
        if (!token) return null;
        // An expired token counts as absent, so the user gets a Sign in button rather
        // than a confusing 401 on their first action.
        if (expiresAt && new Date(expiresAt) <= new Date()) return null;
        return token;
      },

      storeToken: function (payload) {
        var settings = Office.context.roamingSettings;
        settings.set(TOKEN_KEY, payload.access_token);
        settings.set(TOKEN_EXPIRY_KEY, payload.expires_at);
        settings.saveAsync();
      },

      /**
       * Signs in through an Office dialog. The dialog is a top-level window, so the
       * CapHive session cookie works there — unlike in this pane, which is a cross-site
       * iframe. Triggered by a button rather than automatically, because hosts restrict
       * dialogs opened without a user gesture.
       */
      signIn: function () {
        return new Promise(function (resolve, reject) {
          var url = window.location.origin + '/outlook_addin/oauth_start';

          Office.context.ui.displayDialogAsync(url, { height: 60, width: 40 }, function (result) {
            if (result.status !== Office.AsyncResultStatus.Succeeded) {
              reject(new Error('Could not open the sign-in window: ' + result.error.message));
              return;
            }

            var dialog = result.value;
            dialog.addEventHandler(Office.EventType.DialogMessageReceived, function (arg) {
              dialog.close();
              var payload;
              try {
                payload = JSON.parse(arg.message);
              } catch (e) {
                reject(new Error('Sign-in returned an unreadable response.'));
                return;
              }
              if (payload.error) reject(new Error(payload.error));
              else resolve(payload);
            });

            dialog.addEventHandler(Office.EventType.DialogEventReceived, function () {
              dialog.close();
            });
          });
        });
      }
    };
  }

  /**
   * Development simulator. Runs the pane in a plain browser tab against a message you type
   * into a form, so the whole flow — match, confirm, file, undo — can be exercised without
   * sideloading anything into Outlook.
   *
   * Only reachable when the layout sets window.CAPHIVE_SIMULATOR, which it does outside
   * production. Everything below the host boundary is the same code the real add-in runs.
   */
  function SimulatorHost() {
    var itemChangedHandler = null;

    function readForm() {
      return {
        subject: byId('sim-subject').value || '(no subject)',
        from: byId('sim-from').value.trim(),
        to: splitAddresses(byId('sim-to').value),
        cc: splitAddresses(byId('sim-cc').value),
        // Blank stays blank so the "no Message-ID" path can be exercised too.
        internetMessageId: byId('sim-message-id').value.trim(),
        itemId: 'simulated-item-id',
        receivedAt: new Date(),
        // Mirrors the Outlook host so the simulator exercises the same exclusion path.
        mailboxEmail: byId('sim-mailbox').value.trim()
      };
    }

    function splitAddresses(value) {
      return (value || '').split(',').map(function (a) { return a.trim(); }).filter(Boolean);
    }

    return {
      start: function (onReady) {
        byId('simulator-panel').hidden = false;
        // Stands in for selecting a different message in Outlook, which is what makes the
        // ItemChanged path testable at all.
        byId('sim-load').addEventListener('click', function () {
          if (itemChangedHandler) itemChangedHandler();
        });
        onReady();
      },

      onItemChanged: function (handler) { itemChangedHandler = handler; },

      readItem: function () {
        var email = readForm();
        return email.from ? email : null;
      },

      getBody: function () {
        return Promise.resolve(byId('sim-body').value);
      },

      getAttachments: function () {
        var files = byId('sim-attachments').files;
        var attachments = [];
        for (var i = 0; i < files.length; i++) {
          attachments.push({ name: files[i].name, blob: files[i] });
        }
        return Promise.resolve(attachments);
      },

      readStoredToken: function () {
        var token = window.localStorage.getItem(TOKEN_KEY);
        var expiresAt = window.localStorage.getItem(TOKEN_EXPIRY_KEY);
        if (!token) return null;
        if (expiresAt && new Date(expiresAt) <= new Date()) return null;
        return token;
      },

      storeToken: function (payload) {
        window.localStorage.setItem(TOKEN_KEY, payload.access_token);
        window.localStorage.setItem(TOKEN_EXPIRY_KEY, payload.expires_at);
      },

      /**
       * No Office dialog channel here, so the token is fetched straight from the same
       * endpoint the dialog renders — it is same-origin and relies on the ordinary
       * CapHive session cookie, so you must already be logged in in this browser.
       */
      signIn: function () {
        return fetch(window.location.origin + '/outlook_addin/oauth_start.json', {
          credentials: 'include',
          headers: { Accept: 'application/json' }
        }).then(function (response) {
          if (response.status === 401 || response.redirected) {
            throw new Error('Log in to CapHive in another tab first, then try again.');
          }
          if (!response.ok) throw new Error('Could not get a token (HTTP ' + response.status + ').');
          return response.json();
        });
      }
    };
  }

  function signIn() {
    host.signIn().then(function (payload) {
      host.storeToken(payload);
      state.token = payload.access_token;
      showSuccess('Signed in as ' + payload.user_name);
      loadCurrentItem();
    }).catch(function (error) {
      showError(error.message);
    });
  }

  // ---------------------------------------------------------------- api

  function apiFetch(path, options) {
    options = options || {};
    var headers = options.headers || {};
    headers['Authorization'] = 'Bearer ' + state.token;
    if (options.body && !(options.body instanceof FormData)) {
      headers['Content-Type'] = 'application/json';
    }

    return fetch(window.location.origin + path, {
      method: options.method || 'GET',
      headers: headers,
      body: options.body
    }).then(function (response) {
      if (response.status === 401) {
        // The token has expired or been revoked. Drop it and ask for a fresh sign-in
        // instead of surfacing a parse error, which is what the old pane did when it
        // tried to JSON-parse a login redirect.
        state.token = null;
        showSection('signed-out');
        throw new Error('Your CapHive session has expired. Please sign in again.');
      }
      return response.json().then(function (body) {
        if (!response.ok && body && body.errors) throw new Error(body.errors.join(', '));
        return body;
      });
    });
  }

  function matchOwner() {
    showSection('loading');

    apiFetch('/api/v1/mail/match', {
      method: 'POST',
      body: JSON.stringify({
        from_email: state.email.from,
        to_emails: state.email.to,
        cc_emails: state.email.cc,
        mailbox_email: state.email.mailboxEmail,
        internet_message_id: state.email.internetMessageId
      })
    }).then(function (data) {
      state.candidates = data.candidates || [];
      state.filedState = data.filed && data.filed.filed ? data.filed : null;
      renderMatch(data.match_type);
    }).catch(function (error) {
      showSection('ready');
      showError(error.message);
    });
  }

  function renderMatch(matchType) {
    showSection('ready');
    populateOwnerSelect(state.candidates);

    // Already-filed takes priority over everything: the useful answer is "this is already
    // in CapHive", not "here is who I think it belongs to".
    if (state.filedState) {
      var filedBy = state.filedState.filed_by ? ' by ' + state.filedState.filed_by : '';
      showMessage('info', 'Already filed' + filedBy + ' against ' + state.filedState.owner_name + '.', state.filedState.url);
      byId('owner-name').textContent = state.filedState.owner_name;
      byId('file-button').textContent = 'File again to a different record';
      byId('file-button').disabled = true;
      byId('change-owner-button').hidden = false;
      return;
    }

    if (matchType === 'single') {
      selectOwner(state.candidates[0]);
      byId('change-owner-button').hidden = false;
    } else if (matchType === 'multiple') {
      showMessage('warning', 'More than one record matches this email. Choose which one to file against.');
      toggleOwnerPicker(true);
    } else {
      showMessage('warning', 'No matching record found. Search for one to file against.');
      toggleOwnerPicker(true);
    }
  }

  function selectOwner(candidate) {
    if (!candidate) return;
    state.selectedOwnerId = candidate.id;
    byId('owner-name').textContent = candidate.name;
    byId('owner-reason').textContent = candidate.reason ? reasonLabel(candidate.reason) : '';
    byId('file-button').disabled = false;
    byId('owner-select').value = String(candidate.id);
  }

  // Explains *why* a record was matched, so the user can judge it rather than trusting it.
  function reasonLabel(reason) {
    if (reason === 'contact') return 'Matched on a known investor contact';
    if (reason === 'primary_email') return 'Matched on the investor’s primary email';
    if (reason === 'domain') return 'Matched on email domain';
    return '';
  }

  // ---------------------------------------------------------------- owner picker

  function toggleOwnerPicker(forceOpen) {
    var picker = byId('owner-picker');
    picker.hidden = forceOpen === true ? false : !picker.hidden;
    if (!picker.hidden) byId('owner-search').focus();
  }

  function searchOwners() {
    var query = byId('owner-search').value.trim();
    if (query.length < 2) return;

    apiFetch('/api/v1/mail/owners?q=' + encodeURIComponent(query))
      .then(function (data) { populateOwnerSelect(data.owners || []); })
      .catch(function (error) { showError(error.message); });
  }

  function populateOwnerSelect(owners) {
    var select = byId('owner-select');
    select.innerHTML = '';

    var placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = owners.length ? 'Choose a record…' : 'No matches — try searching';
    select.appendChild(placeholder);

    owners.forEach(function (owner) {
      var option = document.createElement('option');
      option.value = String(owner.id);
      // textContent, not innerHTML: investor names are user-supplied.
      option.textContent = owner.name;
      select.appendChild(option);
    });
  }

  function onOwnerSelected(event) {
    var id = event.target.value;
    if (!id) {
      state.selectedOwnerId = null;
      byId('file-button').disabled = true;
      return;
    }
    selectOwner({
      id: parseInt(id, 10),
      name: event.target.options[event.target.selectedIndex].textContent
    });
    byId('file-button').textContent = 'File to CapHive';
  }

  // ---------------------------------------------------------------- filing

  function fileEmail() {
    if (!state.selectedOwnerId) return;

    var button = byId('file-button');
    button.disabled = true;
    button.textContent = 'Filing…';

    host.getBody()
      .then(function (body) {
        return host.getAttachments().then(function (attachments) {
          return submitFiling(body, attachments);
        });
      })
      .catch(function (error) {
        showError(error.message);
        button.disabled = false;
        button.textContent = 'File to CapHive';
      });
  }

  function submitFiling(body, attachments) {
    var form = new FormData();
    form.append('owner_id', state.selectedOwnerId);
    form.append('subject', state.email.subject);
    form.append('body', body);
    form.append('from', state.email.from || '');
    form.append('message_id', state.email.itemId || '');
    // Omitted entirely rather than sent as '' when Office.js does not expose it. An empty
    // string is not NULL, so it would land in the unique dedup index and make two
    // unrelated emails collide.
    if (state.email.internetMessageId) {
      form.append('internet_message_id', state.email.internetMessageId);
    }
    form.append('received_at', state.email.receivedAt ? new Date(state.email.receivedAt).toISOString() : '');
    state.email.to.forEach(function (address) { form.append('to[]', address); });
    state.email.cc.forEach(function (address) { form.append('cc_emails[]', address); });

    attachments.forEach(function (attachment) {
      form.append('attachments[]', attachment.blob, attachment.name);
    });

    return apiFetch('/api/v1/mail/filings', { method: 'POST', body: form })
      .then(function (data) {
        var button = byId('file-button');
        state.lastFilingId = data.id;

        if (data.already_filed) {
          showMessage('info', 'This email was already filed against that record.', data.url);
        } else {
          showMessage('success', 'Filed to CapHive.', data.url);
          byId('undo-button').hidden = false;
        }
        button.textContent = 'Filed';
        button.disabled = true;
      });
  }

  function undoFiling() {
    if (!state.lastFilingId) return;

    apiFetch('/api/v1/mail/filings/' + state.lastFilingId, { method: 'DELETE' })
      .then(function () {
        state.lastFilingId = null;
        byId('undo-button').hidden = true;
        byId('file-button').disabled = false;
        byId('file-button').textContent = 'File to CapHive';
        showMessage('info', 'Filing removed.');
      })
      .catch(function (error) { showError(error.message); });
  }

  function base64ToBlob(base64) {
    var binary = atob(base64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes]);
  }

  // ---------------------------------------------------------------- ui helpers

  function byId(id) { return document.getElementById(id); }

  function showSection(name) {
    ['loading', 'ready', 'signed-out', 'empty'].forEach(function (section) {
      byId('section-' + section).hidden = section !== name;
    });
  }

  function clearMessages() { byId('message-container').innerHTML = ''; }

  /**
   * Builds alerts with DOM APIs rather than innerHTML interpolation — messages can carry
   * server text and record names, and the old pane pasted both straight into innerHTML.
   */
  function showMessage(kind, text, url) {
    var container = byId('message-container');
    container.innerHTML = '';

    var alert = document.createElement('div');
    alert.className = 'mail-addin__alert mail-addin__alert--' + kind;
    alert.appendChild(document.createTextNode(text));

    if (url) {
      var link = document.createElement('a');
      link.href = url;
      link.target = '_blank';
      link.rel = 'noopener';
      link.textContent = 'View in CapHive';
      alert.appendChild(document.createTextNode(' '));
      alert.appendChild(link);
    }

    container.appendChild(alert);
  }

  function showError(message) { showMessage('error', message); }
  function showSuccess(message) { showMessage('success', message); }

  function debounce(fn, wait) {
    var timer;
    return function () {
      var args = arguments, context = this;
      clearTimeout(timer);
      timer = setTimeout(function () { fn.apply(context, args); }, wait);
    };
  }
})();
