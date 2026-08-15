# frozen_string_literal: true

require 'cgi'
require 'json'
require 'open3'
require 'time'

module IncidentWatch
  # Renders the incident store as a single self-contained HTML page.
  #
  # No server and no database: the JSON store is already the source of truth, it is written
  # atomically, and at this scale (tens of incidents) a SQLite layer would add a schema and
  # a migration path without answering a single question faster. The page is regenerated on
  # every poll, so it is never more than one cron tick stale, and it refreshes itself so an
  # in-flight RCA run visibly advances while you watch it.
  class Dashboard
    # Anything seen inside this window is "hot" - still firing right now, not history.
    RECENT_WINDOW = 30 * 60

    # interactive: true renders the action buttons (Create PR, Ignore, Analyse). They are
    # forms that POST, so they only work when the page is served by `incident-watch serve`;
    # a file:// page has nothing to post to. The static file therefore renders read-only,
    # with a pointer to the serve command, rather than dead buttons.
    def initialize(repo_root, config, store, interactive: false, flash: nil, booted_at: nil)
      @repo_root = repo_root
      @config = config
      @store = store
      @interactive = interactive
      @flash = flash
      @booted_at = booted_at
      @now = Time.now.utc
    end

    def render_to(path)
      html = render
      File.write(path, html)
      path
    end

    def render
      incidents = @store.all.sort_by { |i| sort_key(i) }.reverse
      pr_index = pull_requests_by_branch

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <!-- Refresh often enough that a running RCA's progress bar actually moves. -->
        <meta http-equiv="refresh" content="30">
        <title>Production incidents</title>
        <style>#{styles}</style>
        </head>
        <body>
        <header>
          <h1>Production incidents</h1>
          <p class="sub">
            #{incidents.size} tracked &middot; generated #{stamp(@now)} &middot; refreshes every 30s
            #{'&middot; read-only &mdash; run <code>bin/incident-watch serve</code> for action buttons' unless @interactive}
          </p>
        </header>
        #{flash_banner}
        #{stale_code_banner}
        #{review_banner(incidents)}
        #{summary(incidents)}
        #{table(incidents, pr_index)}
        <footer>
          <p>Source of truth: <code>#{h @store.incidents_dir}</code></p>
          <p>Poll now: <code>bundle exec ruby bin/incident-watch poll</code> &nbsp;
             Analyse one: <code>bin/incident-watch dispatch &lt;id&gt;</code></p>
        </footer>
        </body>
        </html>
      HTML
    end

    # A full-page view of one RCA, with the approve button at the bottom.
    #
    # This is a separate page rather than an inline block in the table on purpose: the table
    # is for scanning "what is on fire", and a 150-line document inlined into every row makes
    # that impossible. Approving without reading is the failure mode this whole gate exists
    # to prevent, so the document gets the room it needs.
    def render_rca(incident, markdown)
      return page('RCA not found', '<p class="empty">No RCA recorded for that incident.</p>') if
        incident.nil? || markdown.nil?

      fp = incident['fingerprint']
      approve = if incident['state'] == 'analysed'
                  <<~HTML
                    <div class="approve-bar">
                      <form method="post" action="/approve" class="inline">
                        <input type="hidden" name="fp" value="#{h fp}">
                        <button type="submit" class="primary big">Approve &rarr; write the patch &amp; open a PR</button>
                      </form>
                      <span class="msg">No application code has been changed yet. Approving starts the patch run.</span>
                    </div>
                  HTML
                else
                  "<p class=\"msg\">This incident is <strong>#{h incident['state']}</strong>; the approve step no longer applies.</p>"
                end

      body = <<~HTML
        <header>
          <p class="sub"><a href="/">&larr; All incidents</a></p>
          <h1>#{h incident['exception_class']} <span class="muted">in #{h incident['location'] || 'background'}</span></h1>
          <p class="sub">#{h fp} &middot; #{incident['occurrences']} email(s) &middot; branch <code>#{h incident['branch']}</code></p>
        </header>
        #{approve}
        <article class="rca">#{render_markdown(markdown)}</article>
        #{approve}
      HTML
      page("RCA #{fp}", body)
    end

    private

    # Wrap body content in the same chrome as the dashboard, minus the auto-refresh - a page
    # you are reading must not reload out from under you mid-paragraph.
    def page(title, body)
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h title}</title><style>#{styles}</style></head>
        <body>#{body}</body>
        </html>
      HTML
    end

    # Render the RCA markdown. Redcarpet ships with this app; when it cannot be loaded fall
    # back to preformatted text rather than failing to show the document at all.
    def render_markdown(text)
      @markdown ||= if load_redcarpet
                      Redcarpet::Markdown.new(
                        Redcarpet::Render::HTML.new(escape_html: true, hard_wrap: false),
                        tables: true, fenced_code_blocks: true, autolink: true,
                        strikethrough: true, no_intra_emphasis: true, space_after_headers: true
                      )
                    else
                      :unavailable
                    end

      return "<pre>#{h text}</pre>" if @markdown == :unavailable

      @markdown.render(text)
    end

    def load_redcarpet
      require 'redcarpet'
      true
    rescue LoadError
      begin
        require 'bundler/setup'
        require 'redcarpet'
        true
      rescue StandardError, LoadError
        false
      end
    end

    # --- data helpers -------------------------------------------------------------------

    def sort_key(incident)
      # Running work first, then most recently seen. Sorting is reversed by the caller, so
      # the "running" flag has to be the high bit here.
      # Running work first, ignored last, everything else by recency.
      rank = case incident['state']
             when 'dispatched', 'patching' then 3
             when 'analysed' then 2 # needs your decision - keep it visible
             when 'ignored' then 0
             else 1
             end
      [rank, incident['last_seen'].to_s]
    end

    def parse_time(value)
      value && Time.parse(value.to_s).utc
    rescue ArgumentError, TypeError
      nil
    end

    def age_seconds(value)
      t = parse_time(value)
      t && (@now - t)
    end

    def recent?(incident)
      # An ignored incident is never "firing" for our purposes, however often it recurs -
      # suppressing it from this signal is exactly what ignoring it is for.
      return false if incident['state'] == 'ignored'

      seconds = age_seconds(incident['last_seen'])
      seconds && seconds <= RECENT_WINDOW
    end

    def stamp(time)
      time.getlocal.strftime('%Y-%m-%d %H:%M:%S %Z')
    end

    # "4m ago" reads faster than a timestamp when you are scanning for what is on fire.
    def ago(value)
      seconds = age_seconds(value)
      return '-' unless seconds

      seconds = seconds.to_i
      return "#{seconds}s ago" if seconds < 60
      return "#{seconds / 60}m ago" if seconds < 3600
      return "#{seconds / 3600}h ago" if seconds < 86_400

      "#{seconds / 86_400}d ago"
    end

    # Ask gh once for every open PR, rather than shelling out per incident. Failure here is
    # not fatal - gh may be unauthenticated, or there may be no network - the column just
    # falls back to showing the branch.
    def pull_requests_by_branch
      out, status = Open3.capture2e('gh', 'pr', 'list', '--state', 'all', '--limit', '100',
                                    '--json', 'number,url,state,headRefName')
      return {} unless status.success?

      # rubocop:disable Rails/IndexBy -- index_by is ActiveSupport; nothing here boots Rails,
      # so it would raise NoMethodError at runtime. Core Hash#to_h is the correct tool.
      JSON.parse(out).to_h { |pr| [pr['headRefName'], pr] }
      # rubocop:enable Rails/IndexBy
    rescue StandardError
      {}
    end

    def branch_exists?(branch)
      return false if branch.to_s.empty?

      system('git', '-C', @repo_root, 'rev-parse', '--verify', '--quiet', "refs/heads/#{branch}",
             out: File::NULL, err: File::NULL)
    end

    # --- sections -----------------------------------------------------------------------

    def summary(incidents)
      by_state = incidents.group_by { |i| i['state'] }
      hot = incidents.count { |i| recent?(i) }
      occurrences = incidents.sum { |i| i['occurrences'].to_i }

      cards = [
        ['Firing in last 30m', hot, hot.positive? ? 'hot' : 'quiet'],
        ['Awaiting analysis', by_state['new']&.size || 0, 'new'],
        ['Running', (by_state['dispatched']&.size || 0) + (by_state['patching']&.size || 0), 'running'],
        ['Awaiting your review', by_state['analysed']&.size || 0,
         (by_state['analysed']&.size || 0).positive? ? 'review' : 'muted'],
        ['Patched', by_state['done']&.size || 0, 'done'],
        ['Failed', by_state['failed']&.size || 0, 'failed'],
        ['Ignored (bad data)', by_state['ignored']&.size || 0, 'muted'],
        ['Total emails', occurrences, 'muted']
      ]

      <<~HTML
        <section class="cards">
          #{cards.map { |label, value, kind| card(label, value, kind) }.join("\n")}
        </section>
      HTML
    end

    # The static file:// page has no buttons - it cannot POST anywhere. Without this banner
    # it reports "3 awaiting your review" and then offers no way whatsoever to review them,
    # which is a dead end rather than a dashboard. Say plainly what to run.
    # Show what just went wrong. Without this an action that fails redirects to an unchanged
    # page, which looks exactly like a button that does nothing.
    def flash_banner
      return '' if @flash.to_s.empty?

      %(<section class="banner error">#{h @flash}</section>)
    end

    # Ruby reads these files once, at boot. Editing them afterwards does not affect a running
    # server, and the symptom - a button that silently does nothing - is genuinely hard to
    # place. If anything the server depends on is newer than the server, say so.
    def stale_code_banner
      return '' unless @booted_at

      sources = Dir[File.join(@repo_root, 'lib', 'incident_watch', '*.rb')] +
                [File.join(@repo_root, 'bin', 'incident-watch')]
      newer = sources.select { |f| File.exist?(f) && File.mtime(f) > @booted_at }
      return '' if newer.empty?

      <<~HTML
        <section class="banner error">
          <strong>This server is running stale code.</strong>
          #{newer.size} source file(s) changed since it started
          (#{@booted_at.getlocal.strftime('%H:%M:%S')}). Buttons may fail silently or behave
          unexpectedly until you restart it.
          <div class="mono">Ctrl-C, then: bin/incident-watch serve --open</div>
        </section>
      HTML
    end

    def review_banner(incidents)
      awaiting = incidents.select { |i| i['state'] == 'analysed' }
      return '' if awaiting.empty?

      return "<section class=\"banner\"><strong>#{awaiting.size} RCA(s) awaiting your review.</strong> Use <em>Read RCA</em> in the Actions column, then <em>Approve</em>.</section>" if @interactive

      commands = awaiting.map do |incident|
        %(<div class="mono">bin/incident-watch rca #{h incident['fingerprint']}) +
          %(  <span class="muted"># #{h incident['exception_class']} in #{h incident['location'] || 'background'}</span></div>)
      end

      <<~HTML
        <section class="banner">
          <strong>#{awaiting.size} RCA(s) are waiting for your decision</strong> &mdash; and this page
          cannot act on them, because it was opened as a file rather than served.
          <p>Start the server to get <em>Read RCA</em> and <em>Approve</em> buttons:</p>
          <div class="mono">bin/incident-watch serve --open</div>
          <p>Or read and approve from the terminal:</p>
          #{commands.join}
          <div class="mono">bin/incident-watch approve &lt;id&gt;</div>
        </section>
      HTML
    end

    def card(label, value, kind)
      %(<div class="card #{kind}"><div class="value">#{value}</div><div class="label">#{h label}</div></div>)
    end

    def table(incidents, pr_index)
      return '<p class="empty">No incidents recorded yet. Run <code>bin/incident-watch poll</code>.</p>' if
        incidents.empty?

      rows = incidents.map { |i| row(i, pr_index) }.join("\n")

      <<~HTML
        <table>
          <thead>
            <tr>
              <th>Incident</th><th>Exception</th><th>Where</th>
              <th class="num">Emails</th><th>Last seen</th><th>Status</th><th>Branch / PR</th>
              #{'<th>Actions</th>' if @interactive}
            </tr>
          </thead>
          <tbody>
        #{rows}
          </tbody>
        </table>
      HTML
    end

    def row(incident, pr_index)
      classes = []
      classes << 'recent' if recent?(incident)
      classes << 'running' if %w[dispatched patching].include?(incident['state'])
      classes << 'review' if incident['state'] == 'analysed'
      classes << 'ignored' if incident['state'] == 'ignored'

      <<~HTML
        <tr class="#{classes.join(' ')}">
          <td class="mono">#{h incident['fingerprint']}#{recent_badge(incident)}</td>
          <td class="exc">#{h incident['exception_class']}
            <div class="msg">#{h truncate(incident['message'], 150)}</div>
          </td>
          <td>#{h incident['location'] || '-'}#{culprit(incident)}</td>
          <td class="num">#{incident['occurrences']}</td>
          <td class="ts" title="#{h incident['last_seen']}">#{ago(incident['last_seen'])}</td>
          <td>#{status_cell(incident)}</td>
          <td>#{branch_cell(incident, pr_index)}</td>
          #{"<td>#{actions_cell(incident)}</td>" if @interactive}
        </tr>
      HTML
    end

    # What you can do to this incident right now. Deliberately few: the decision the
    # dashboard exists to support is "is this fix worth a PR?", so that is the primary
    # button, and it only appears once there is something to publish.
    def actions_cell(incident)
      fp = incident['fingerprint']
      state = incident['state']
      buttons = []

      if state == 'analysed'
        # The whole point of the gate: read the RCA, then decide. Reading comes first
        # because approving without reading is the failure mode this design exists to stop.
        buttons << %(<a class="btn" href="/rca?fp=#{h fp}">Read RCA</a>)
        buttons << form('/approve', fp, 'Approve &rarr; patch &amp; PR', primary: true, raw: true)
      end
      buttons << form('/publish', fp, 'Create PR', primary: true) if state == 'done' && incident['pr_url'].nil?
      buttons << form('/dispatch', fp, 'Analyse') if state == 'new'
      buttons << form('/dispatch', fp, 'Retry') if state == 'failed'
      # Stopping matters more than it looks: a run left going spends tokens on an incident
      # you may have already decided you do not care about.
      buttons << form('/stop', fp, 'Stop') if %w[dispatched patching].include?(state)

      if state == 'ignored'
        buttons << form('/unignore', fp, 'Un-ignore')
      # rubocop:disable Rails/NegateInclude -- exclude? is ActiveSupport; nothing here boots
      # Rails, so it raises NoMethodError at runtime.
      elsif !%w[dispatched patching].include?(state)
        # rubocop:enable Rails/NegateInclude
        # A reason is required for the same rationale as the CLI: an unexplained muted
        # incident is indistinguishable from a bug in the matcher six months later.
        buttons << <<~HTML.strip
          <form method="post" action="/ignore" class="inline">
            <input type="hidden" name="fp" value="#{h fp}">
            <input type="text" name="reason" placeholder="why is this bad data?" required>
            <button type="submit">Ignore</button>
          </form>
        HTML
      end

      buttons.join(' ')
    end

    # raw: true passes the label through unescaped, for labels that contain HTML entities
    # (the arrow in "Approve → patch & PR"). Everything else is escaped.
    def form(action, fingerprint, label, primary: false, raw: false)
      %(<form method="post" action="#{action}" class="inline">) +
        %(<input type="hidden" name="fp" value="#{h fingerprint}">) +
        %(<button type="submit" class="#{'primary' if primary}">#{raw ? label : h(label)}</button></form>)
    end

    def recent_badge(incident)
      recent?(incident) ? '<span class="badge hot">live</span>' : ''
    end

    def culprit(incident)
      culprit = incident['culprit']
      return '' unless culprit

      %(<div class="msg mono">#{h culprit['path']}:#{culprit['line']}</div>)
    end

    # The progress indicator. A dispatched incident has a Claude run in flight; show how far
    # into its timeout budget it is, so a wedged run is obvious rather than looking merely
    # slow. The page refresh advances it.
    def status_cell(incident)
      state = incident['state']
      if state == 'analysed'
        # Not "finished" - waiting on a person. Say so, rather than showing a neutral pill
        # that looks like nothing needs doing.
        return %(<span class="pill analysed">awaiting your review</span>) +
               %(<div class="msg">RCA written, no code changed yet</div>)
      end
      if state == 'ignored'
        # The reason is the whole value of an ignored row - without it, a muted incident is
        # indistinguishable from a bug in the matcher.
        source = incident['ignored_by_rule'] ? 'rule' : 'manual'
        return "<span class=\"pill ignored\">ignored</span><div class=\"msg\">#{h incident['ignored_reason']} <em>(#{source})</em></div>"
      end
      return %(<span class="pill #{state}">#{h state}</span>) unless %w[dispatched patching].include?(state)

      elapsed = age_seconds(incident['state_changed_at']) || 0
      budget = @config.dig('dispatch', 'timeout_seconds').to_i
      budget = 1800 if budget <= 0
      # Floor at 2% so a just-started run still shows a visible sliver rather than an empty
      # bar that reads as "nothing is happening".
      pct = (elapsed / budget.to_f * 100).round.clamp(2, 100)

      <<~HTML.strip
        <span class="pill dispatched">#{state == 'patching' ? 'patching' : 'analysing'}</span>
        <div class="bar" title="#{elapsed.to_i}s of #{budget}s budget">
          <div class="fill" style="width:#{pct}%"></div>
        </div>
        <div class="msg">#{(elapsed / 60).to_i}m elapsed of #{budget / 60}m</div>
      HTML
    end

    def branch_cell(incident, pr_index)
      branch = incident['branch']
      return '<span class="muted">-</span>' if branch.to_s.empty?

      # Prefer what the dispatcher recorded when it opened the PR - that is authoritative and
      # free. The gh lookup is a fallback for PRs opened by hand, and degrades to "local
      # only" when gh is unavailable rather than pretending no PR exists.
      pr = pr_index[branch]
      url = incident['pr_url'] || pr&.dig('url')
      number = incident['pr_number'] || pr&.dig('number')

      parts = []
      parts << if url
                 # A button, not a bare link: this is the primary action on the whole page -
                 # go read the diff and merge it.
                 %(<a class="btn primary" href="#{h url}">Review PR ##{number}</a>)
               elsif branch_exists?(branch)
                 '<span class="muted">local only</span> '
               else
                 '<span class="muted">branch gone</span> '
               end
      parts << %(<div class="msg mono">#{h branch}</div>)
      # Surface a failed push/PR attempt: the branch is fine, but it did not get published.
      parts << %(<div class="msg err">#{h incident['pr_error']}</div>) if incident['pr_error']
      # The RCA normally lives in the PR body. When there is no PR it would otherwise be
      # unreachable from here, so point at it on the branch rather than leaving a dead end.
      parts << %(<div class="msg mono">git show #{h branch}:#{h incident['rca_doc']}</div>) if url.nil? && incident['rca_doc']
      parts << %(<div class="msg">#{h incident['error']}</div>) if incident['error']
      parts.join
    end

    def truncate(value, max)
      str = value.to_s.tr("\n", ' ')
      str.length > max ? "#{str[0, max]}..." : str
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    def styles
      <<~CSS
        :root {
          --bg: #f6f7f9; --fg: #14161a; --muted: #6b7280; --line: #e2e5ea; --panel: #ffffff;
          --hot: #d92d20; --hot-bg: #fef3f2; --run: #b54708; --run-bg: #fffaeb;
          --ok: #067647; --ok-bg: #ecfdf3; --new: #175cd3; --new-bg: #eff8ff;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #0f1115; --fg: #e6e8ec; --muted: #9aa1ac; --line: #262b33; --panel: #161a20;
            --hot: #ff6b6b; --hot-bg: #2a1614; --run: #f5a524; --run-bg: #2a2113;
            --ok: #4ade80; --ok-bg: #10231a; --new: #7cb7ff; --new-bg: #111e2e;
          }
        }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 24px; background: var(--bg); color: var(--fg);
               font: 14px/1.5 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; }
        h1 { margin: 0; font-size: 22px; letter-spacing: -0.01em; }
        .sub { margin: 4px 0 20px; color: var(--muted); font-size: 13px; }
        .cards { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; }
        .card { flex: 1 1 130px; background: var(--panel); border: 1px solid var(--line);
                border-radius: 10px; padding: 12px 14px; }
        .card .value { font-size: 26px; font-weight: 650; letter-spacing: -0.02em; }
        .card .label { color: var(--muted); font-size: 12px; margin-top: 2px; }
        .card.hot { border-color: var(--hot); background: var(--hot-bg); }
        .card.hot .value { color: var(--hot); }
        .card.running .value { color: var(--run); }
        .card.done .value { color: var(--ok); }
        table { width: 100%; border-collapse: collapse; background: var(--panel);
                border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
        th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line);
                 vertical-align: top; }
        th { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em;
             color: var(--muted); font-weight: 600; }
        td.num, th.num { text-align: right; }
        tr.recent td { background: var(--hot-bg); }
        tr.running td { background: var(--run-bg); }
        tr.rca-row td { background: transparent; }
        .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
        .exc { font-weight: 600; }
        .msg { color: var(--muted); font-weight: 400; font-size: 12px; margin-top: 3px;
               word-break: break-word; }
        .muted { color: var(--muted); }
        .msg.err { color: var(--hot); }
        .badge { margin-left: 6px; padding: 1px 6px; border-radius: 999px; font-size: 10px;
                 font-weight: 700; text-transform: uppercase; }
        .badge.hot { background: var(--hot); color: #fff; }
        .pill { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 12px;
                font-weight: 600; }
        .pill.new { background: var(--new-bg); color: var(--new); }
        .pill.dispatched { background: var(--run-bg); color: var(--run); }
        .pill.done { background: var(--ok-bg); color: var(--ok); }
        .pill.failed { background: var(--hot-bg); color: var(--hot); }
        .pill.ignored { background: var(--bg); color: var(--muted); }
        .pill.analysed, .pill.patching { background: var(--new-bg); color: var(--new); }
        .card.review { border-color: var(--new); background: var(--new-bg); }
        .card.review .value { color: var(--new); }
        tr.review td { background: var(--new-bg); }
        tr.ignored td { opacity: 0.55; }
        tr.ignored:hover td { opacity: 1; }
        .bar { margin-top: 6px; height: 5px; width: 110px; background: var(--line);
               border-radius: 999px; overflow: hidden; }
        .bar .fill { height: 100%; background: var(--run); border-radius: 999px;
                     transition: width 1s linear; }
        form.inline { display: inline-flex; gap: 4px; align-items: center; margin: 2px 0; }
        form.inline input[type=text] { font: inherit; font-size: 12px; padding: 3px 7px;
              border: 1px solid var(--line); border-radius: 6px; background: var(--bg);
              color: var(--fg); width: 150px; }
        form.inline button { font: inherit; font-size: 12px; font-weight: 600; cursor: pointer;
              padding: 4px 10px; border-radius: 6px; border: 1px solid var(--line);
              background: var(--panel); color: var(--fg); }
        form.inline button:hover { border-color: var(--new); }
        form.inline button.primary { background: var(--new); border-color: var(--new); color: #fff; }
        /* RCA reading view - document typography, not table typography. */
        .rca { max-width: 860px; margin: 8px 0 24px; }
        .rca h1 { font-size: 19px; margin: 16px 0 6px; }
        .rca h2 { font-size: 15px; margin: 20px 0 6px; padding-bottom: 4px;
                  border-bottom: 1px solid var(--line); }
        .rca h3 { font-size: 13px; margin: 14px 0 4px; }
        .rca p, .rca li { font-size: 13.5px; line-height: 1.65; }
        .rca ul, .rca ol { padding-left: 20px; }
        .rca table { width: auto; border: 1px solid var(--line); margin: 10px 0; }
        .rca th, .rca td { padding: 6px 10px; font-size: 12px; }
        .rca code { background: var(--bg); padding: 1px 5px; border-radius: 4px; }
        .rca pre { background: var(--bg); border: 1px solid var(--line); border-radius: 8px;
                   padding: 12px; overflow-x: auto; font-size: 12px; white-space: pre-wrap; }
        .rca pre code { background: none; padding: 0; }
        .approve-bar { display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
                       background: var(--panel); border: 1px solid var(--line);
                       border-radius: 10px; padding: 12px 14px; margin: 14px 0; }
        button.big { font-size: 13px; padding: 8px 16px; }
        .btn { display: inline-block; padding: 4px 11px; border-radius: 7px; font-size: 12px;
               font-weight: 600; text-decoration: none; border: 1px solid var(--line);
               color: var(--fg); background: var(--panel); }
        .btn.primary { background: var(--new); border-color: var(--new); color: #fff; }
        .btn.primary:hover { filter: brightness(1.08); }
        pre { background: var(--bg); border: 1px solid var(--line); border-radius: 8px;
              padding: 12px; overflow-x: auto; font-size: 12px; line-height: 1.45;
              white-space: pre-wrap; word-break: break-word; max-height: 60vh; }
        a { color: var(--new); }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
        footer { margin-top: 18px; color: var(--muted); font-size: 12px; }
        .banner { background: var(--new-bg); border: 1px solid var(--new); border-radius: 10px;
                  padding: 14px 16px; margin-bottom: 16px; font-size: 13px; line-height: 1.6; }
        .banner p { margin: 10px 0 4px; }
        .banner.error { background: var(--hot-bg); border-color: var(--hot); }
        .banner .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                        font-size: 12px; background: var(--panel); border: 1px solid var(--line);
                        border-radius: 6px; padding: 6px 9px; margin: 3px 0; overflow-x: auto; }
        .empty { background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
                 padding: 24px; text-align: center; color: var(--muted); }
      CSS
    end
  end
end
