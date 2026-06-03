# Generates a polished marketing email draft from the last N days of git commits.
# Usage:
#   rake irm:weekly_email                  # last 7 days, product name = CapHive
#   rake irm:weekly_email DAYS=14          # last 14 days
#   rake irm:weekly_email PRODUCT=MyApp    # override product name

module WeeklyEmailTask
  SECTION_ACCENT_COLORS = %w[#1B5E99 #0D7B6B #7B3FA6 #B45309].freeze
  DEFAULT_RECIPIENT     = "support@caphive.com"
  DEFAULT_SENDER        = ENV.fetch("SUPPORT_EMAIL_FROM", "support@caphive.com")

  # Loads SMTP credentials from a specific Rails credentials environment (e.g. "staging.in")
  # without requiring that environment's database to be reachable.
  def self.smtp_settings_for(creds_env)
    env_file = Rails.root.join(".env.#{creds_env}")
    env_vars = env_file.exist? ? parse_env_file(env_file) : {}

    smtp_server = env_vars["SMTP_SERVER"] || ENV.fetch("SMTP_SERVER", "email-smtp.ap-south-1.amazonaws.com")

    creds = ActiveSupport::EncryptedConfiguration.new(
      config_path: Rails.root.join("config/credentials/#{creds_env}.yml.enc"),
      key_path:    Rails.root.join("config/credentials/#{creds_env}.key"),
      env_key:     "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )

    {
      address:              smtp_server,
      port:                 587,
      domain:               "caphive.com",
      user_name:            creds[:SES_SMTP_USERNAME],
      password:             creds[:SES_SMTP_PASSWORD],
      authentication:       :login,
      enable_starttls_auto: true,
      # Return the verified sender so the task can use it as FROM
      _from:                env_vars["SUPPORT_EMAIL_FROM"] || "support@caphive.com"
    }
  end

  def self.parse_env_file(path)
    path.readlines.each_with_object({}) do |line, h|
      next if line.match?(/\A\s*#/) || line.strip.empty?
      key, val = line.strip.split("=", 2)
      h[key] = val&.gsub(/\A['"]|['"]\z/, "")
    end
  end

  # Minimal inline mailer — always delivers via SES SMTP regardless of env delivery_method
  class ProductMailer < ActionMailer::Base
    layout false
    self.delivery_method = :smtp

    def weekly_update(to:, from:, subject:, html:, smtp_settings:)
      @html_content = html
      mail(
        to: to,
        from: from,
        subject: subject,
        delivery_method_options: smtp_settings
      ) do |format|
        format.html { render inline: @html_content }
      end
    end
  end

  # Each commit is a hash: { message: String, diff: String }
  def self.build_prompt(feat_commits, fix_commits, product_name)
    feat_block = feat_commits.map do |c|
      title = c[:message].sub(/\AFeat:\s*/i, "")
      diff  = c[:diff].presence ? "\n#{c[:diff]}" : ""
      "### #{title}#{diff}"
    end.join("\n\n")

    fix_block = fix_commits.map do |c|
      title = c[:message].sub(/\AFix:\s*/i, "")
      diff  = c[:diff].presence ? "\n#{c[:diff]}" : ""
      "### #{title}#{diff}"
    end.join("\n\n")

    <<~PROMPT
      You are writing a weekly product update email for fund managers and General Partners (GPs)
      using #{product_name}, an investor relations management platform.

      Below are the actual code changes made this week (git diffs for app/packs only).
      Use the diffs to understand WHAT truly changed — not just the commit title — so you can
      write accurate, specific business impact statements. Translate everything into plain English
      for a senior GP or CFO: outcome-first, zero engineering jargon, confident tone.

      FEATURE CHANGES this week:
      #{feat_block.presence || "(none)"}

      BUG FIXES / MINOR CHANGES this week:
      #{fix_block.presence || "(none)"}

      Return ONLY a JSON object with this exact structure (no markdown, no explanation):
      {
        "subject": "Email subject line, under 60 chars, benefit-led",
        "preview_text": "Email preview snippet shown in inbox, under 90 chars",
        "sections": [
          {
            "title": "Business-friendly section title (e.g. 'Smarter Portfolio Insights')",
            "items": [
              {
                "headline": "Outcome-led headline, max 8 words",
                "impact": "2–3 sentences. What does this mean for the GP? Time saved, better decisions, reduced risk, clearer reporting. Concrete and specific."
              }
            ]
          }
        ],
        "misc_improvements": [
          "One positive, non-technical line per fix"
        ]
      }

      Rules:
      - Group related features into 2–4 thematic sections. Never repeat the word "feature".
      - Headlines must focus on OUTCOMES, not mechanics. "Instantly understand AI-generated insights" beats "AI explanation added".
      - Sections should feel distinct — avoid repetitive section titles.
      - misc_improvements should be brief, upbeat, and plain-English. Omit this key if there are no fixes.
      - Output ONLY valid JSON. Do not wrap it in markdown code fences.
    PROMPT
  end

  # ── Internal report helpers ───────────────────────────────────────────────

  def self.build_internal_prompt(feat_commits, fix_commits, other_commits, product_name)
    block = ->(group, label) do
      return "" if group.empty?
      body = group.map do |c|
        title = c[:message].sub(/\A\w+:\s*/i, "")
        diff  = c[:diff].presence ? "\n#{c[:diff]}" : ""
        "### #{title}#{diff}"
      end.join("\n\n")
      "#{label}:\n#{body}"
    end

    sections = [
      block.call(feat_commits,  "FEATURES"),
      block.call(fix_commits,   "BUG FIXES"),
      block.call(other_commits, "REFACTORS / OTHER")
    ].reject(&:blank?).join("\n\n---\n\n")

    <<~PROMPT
      You are producing a detailed internal engineering update for the #{product_name} team
      (developers, product managers, and technical leads).

      Below are this week's git diffs (app/packs only). Read the actual code changes carefully
      and produce a high-fidelity summary. Technical terms, class names, and module references
      are fine. Be specific and accurate — this is for the team, not clients.

      #{sections}

      Return ONLY a JSON object with this exact structure (no markdown, no explanation):
      {
        "title": "Internal Engineering Update — <date range e.g. May 27 – Jun 3, 2026>",
        "summary": "2–3 sentence plain-English summary of the week's themes and overall direction.",
        "sections": [
          {
            "area": "Area name matching the app domain (e.g. 'AI & Formula Engine', 'Deal Management', 'Fund Ratios')",
            "items": [
              {
                "headline": "Concise change title (can be technical)",
                "what_changed": "1–2 sentences describing exactly what was built or changed, including key classes/services/components touched.",
                "why_it_matters": "1–2 sentences on the product or team impact: what it unblocks, fixes, or improves."
              }
            ]
          }
        ],
        "fixes": [
          {
            "headline": "Fix title",
            "detail": "One sentence on what was broken and how it was resolved."
          }
        ],
        "other": [
          "One line per refactor / test / doc change"
        ]
      }

      Rules:
      - Group by product area (not by commit). Merge related commits into one item if they form a single logical change.
      - Be exhaustive — include every meaningful change. Internal readers want the full picture.
      - "fixes" and "other" keys may be omitted if empty.
      - Output ONLY valid JSON. Do not wrap it in markdown code fences.
    PROMPT
  end

  def self.render_internal_html(data, product_name, date_str)
    sections_html = data["sections"].each_with_index.map do |section, idx|
      color = SECTION_ACCENT_COLORS[idx % SECTION_ACCENT_COLORS.size]
      items_html = section["items"].map do |item|
        <<~ITEM
          <div class="change-item">
            <div class="change-headline">#{ERB::Util.html_escape(item["headline"])}</div>
            <div class="change-row">
              <span class="change-label">What changed</span>
              <span class="change-text">#{ERB::Util.html_escape(item["what_changed"])}</span>
            </div>
            <div class="change-row">
              <span class="change-label">Why it matters</span>
              <span class="change-text">#{ERB::Util.html_escape(item["why_it_matters"])}</span>
            </div>
          </div>
        ITEM
      end.join

      <<~SECTION
        <div class="area-section" style="border-top: 3px solid #{color}">
          <div class="area-title" style="color: #{color}">#{ERB::Util.html_escape(section["area"])}</div>
          #{items_html}
        </div>
      SECTION
    end.join

    fixes_html = if data["fixes"]&.any?
      items = data["fixes"].map do |f|
        <<~FIX
          <div class="fix-item">
            <span class="fix-headline">#{ERB::Util.html_escape(f["headline"])}</span>
            <span class="fix-detail"> — #{ERB::Util.html_escape(f["detail"])}</span>
          </div>
        FIX
      end.join
      "<div class='fixes-section'><div class='fixes-title'>Bug Fixes</div>#{items}</div>"
    else
      ""
    end

    other_html = if data["other"]&.any?
      items = data["other"].map { |o| "<li>#{ERB::Util.html_escape(o)}</li>" }.join
      "<div class='other-section'><div class='other-title'>Refactors &amp; Other</div><ul class='other-list'>#{items}</ul></div>"
    else
      ""
    end

    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{ERB::Util.html_escape(data["title"])}</title>
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

          body {
            background: #F0F2F5;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            color: #1E293B;
            padding: 32px 16px 64px;
            font-size: 14px;
            line-height: 1.6;
          }

          .wrapper { max-width: 780px; margin: 0 auto; }

          /* ── Internal badge ── */
          .internal-badge {
            text-align: center;
            margin-bottom: 16px;
          }
          .internal-badge span {
            display: inline-block;
            background: #FEE2E2;
            border: 1px solid #FCA5A5;
            color: #991B1B;
            font-size: 10px;
            font-weight: 800;
            letter-spacing: 2px;
            text-transform: uppercase;
            padding: 4px 14px;
            border-radius: 99px;
          }

          /* ── Header ── */
          .header {
            background: #0F172A;
            border-radius: 10px 10px 0 0;
            padding: 28px 36px;
          }
          .header-eyebrow {
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 2.5px;
            text-transform: uppercase;
            color: #64748B;
            margin-bottom: 8px;
          }
          .header-title {
            font-size: 22px;
            font-weight: 700;
            color: #F1F5F9;
            margin-bottom: 12px;
          }
          .header-summary {
            font-size: 14px;
            color: #94A3B8;
            line-height: 1.7;
            max-width: 620px;
          }

          /* ── Body ── */
          .body {
            background: #FFFFFF;
            padding: 32px 36px;
            border-left: 1px solid #E2E8F0;
            border-right: 1px solid #E2E8F0;
          }

          /* ── Area sections ── */
          .area-section {
            margin-bottom: 32px;
            padding-top: 20px;
          }
          .area-title {
            font-size: 10px;
            font-weight: 800;
            letter-spacing: 2px;
            text-transform: uppercase;
            margin-bottom: 16px;
          }

          /* ── Change items ── */
          .change-item {
            background: #F8FAFC;
            border: 1px solid #E2E8F0;
            border-radius: 6px;
            padding: 14px 16px;
            margin-bottom: 10px;
          }
          .change-headline {
            font-size: 14px;
            font-weight: 700;
            color: #0F172A;
            margin-bottom: 10px;
          }
          .change-row {
            display: flex;
            gap: 10px;
            margin-bottom: 6px;
            align-items: baseline;
          }
          .change-row:last-child { margin-bottom: 0; }
          .change-label {
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 1px;
            text-transform: uppercase;
            color: #94A3B8;
            white-space: nowrap;
            min-width: 110px;
          }
          .change-text {
            font-size: 13px;
            color: #475569;
          }

          /* ── Bug fixes ── */
          .fixes-section {
            margin-top: 24px;
            padding: 18px 20px;
            background: #FFF7ED;
            border: 1px solid #FED7AA;
            border-radius: 6px;
          }
          .fixes-title {
            font-size: 10px;
            font-weight: 800;
            letter-spacing: 2px;
            text-transform: uppercase;
            color: #C2410C;
            margin-bottom: 12px;
          }
          .fix-item {
            font-size: 13px;
            margin-bottom: 6px;
            line-height: 1.5;
          }
          .fix-item:last-child { margin-bottom: 0; }
          .fix-headline { font-weight: 600; color: #431407; }
          .fix-detail   { color: #7C2D12; }

          /* ── Other / refactors ── */
          .other-section {
            margin-top: 20px;
            padding: 18px 20px;
            background: #F8FAFC;
            border: 1px solid #E2E8F0;
            border-radius: 6px;
          }
          .other-title {
            font-size: 10px;
            font-weight: 800;
            letter-spacing: 2px;
            text-transform: uppercase;
            color: #64748B;
            margin-bottom: 12px;
          }
          .other-list { list-style: none; padding: 0; }
          .other-list li {
            font-size: 13px;
            color: #64748B;
            padding: 3px 0 3px 16px;
            position: relative;
          }
          .other-list li::before {
            content: "›";
            position: absolute;
            left: 0;
            color: #CBD5E1;
          }

          /* ── Footer ── */
          .footer {
            background: #0F172A;
            border-radius: 0 0 10px 10px;
            padding: 16px 36px;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }
          .footer-left {
            font-size: 11px;
            color: #475569;
            font-weight: 600;
          }
          .footer-right {
            font-size: 11px;
            color: #334155;
          }
        </style>
      </head>
      <body>
        <div class="wrapper">

          <div class="internal-badge"><span>Internal — Not for client distribution</span></div>

          <div class="header">
            <div class="header-eyebrow">#{ERB::Util.html_escape(product_name)} · Engineering</div>
            <div class="header-title">#{ERB::Util.html_escape(data["title"])}</div>
            <div class="header-summary">#{ERB::Util.html_escape(data["summary"])}</div>
          </div>

          <div class="body">
            #{sections_html}
            #{fixes_html}
            #{other_html}
          </div>

          <div class="footer">
            <span class="footer-left">#{ERB::Util.html_escape(product_name)} Internal</span>
            <span class="footer-right">Generated #{date_str}</span>
          </div>

        </div>
      </body>
      </html>
    HTML
  end

  # ── External email HTML renderer ─────────────────────────────────────────

  def self.render_html(data, product_name, date_str, draft: true)
    sections_html = data["sections"].each_with_index.map do |section, idx|
      color = SECTION_ACCENT_COLORS[idx % SECTION_ACCENT_COLORS.size]
      items_html = section["items"].map do |item|
        <<~ITEM
          <div class="feature-item">
            <div class="feature-headline">#{ERB::Util.html_escape(item["headline"])}</div>
            <div class="feature-impact">#{ERB::Util.html_escape(item["impact"])}</div>
          </div>
        ITEM
      end.join

      <<~SECTION
        <div class="section" style="border-left: 4px solid #{color}">
          <div class="section-title" style="color: #{color}">#{ERB::Util.html_escape(section["title"])}</div>
          #{items_html}
        </div>
      SECTION
    end.join

    misc_html = if data["misc_improvements"]&.any?
      bullets = data["misc_improvements"].map do |item|
        "<li>#{ERB::Util.html_escape(item)}</li>"
      end.join("\n")
      <<~MISC
        <div class="misc-section">
          <div class="misc-title">Misc Improvements</div>
          <ul class="misc-list">#{bullets}</ul>
        </div>
      MISC
    else
      ""
    end

    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{ERB::Util.html_escape(data["subject"])}</title>
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

          body {
            background: #EEF2F7;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            color: #1E293B;
            padding: 32px 16px 48px;
          }

          .email-wrapper {
            max-width: 620px;
            margin: 0 auto;
          }

          /* ── Header ── */
          .header {
            background: linear-gradient(135deg, #0F2D5A 0%, #1B3A6B 100%);
            border-radius: 12px 12px 0 0;
            padding: 36px 40px 28px;
            text-align: center;
          }
          .header-product {
            font-size: 13px;
            font-weight: 700;
            letter-spacing: 3px;
            text-transform: uppercase;
            color: #93C5FD;
            margin-bottom: 10px;
          }
          .header-headline {
            font-size: 26px;
            font-weight: 700;
            color: #FFFFFF;
            line-height: 1.3;
            margin-bottom: 16px;
          }
          .header-meta {
            display: inline-block;
            background: rgba(255,255,255,0.12);
            color: #CBD5E1;
            font-size: 12px;
            padding: 4px 14px;
            border-radius: 99px;
          }

          /* ── Preview bar ── */
          .preview-bar {
            background: #1E4D8C;
            padding: 14px 40px;
            text-align: center;
            color: #BFDBFE;
            font-size: 14px;
            line-height: 1.5;
            font-style: italic;
          }

          /* ── Body ── */
          .body {
            background: #FFFFFF;
            padding: 36px 40px;
          }

          .intro {
            color: #475569;
            font-size: 15px;
            line-height: 1.7;
            margin-bottom: 32px;
            padding-bottom: 24px;
            border-bottom: 1px solid #E2E8F0;
          }

          /* ── Sections ── */
          .section {
            margin-bottom: 28px;
            padding: 20px 20px 20px 24px;
            background: #F8FAFC;
            border-radius: 8px;
          }
          .section-title {
            font-size: 11px;
            font-weight: 800;
            letter-spacing: 2px;
            text-transform: uppercase;
            margin-bottom: 16px;
          }
          .feature-item {
            margin-bottom: 16px;
            padding-bottom: 16px;
            border-bottom: 1px solid #E2E8F0;
          }
          .feature-item:last-child {
            margin-bottom: 0;
            padding-bottom: 0;
            border-bottom: none;
          }
          .feature-headline {
            font-size: 16px;
            font-weight: 700;
            color: #0F172A;
            margin-bottom: 6px;
            line-height: 1.4;
          }
          .feature-impact {
            font-size: 14px;
            color: #475569;
            line-height: 1.7;
          }

          /* ── Misc improvements ── */
          .misc-section {
            margin-top: 28px;
            padding: 20px 24px;
            background: #F1F5F9;
            border-radius: 8px;
            border: 1px solid #E2E8F0;
          }
          .misc-title {
            font-size: 11px;
            font-weight: 800;
            letter-spacing: 2px;
            text-transform: uppercase;
            color: #64748B;
            margin-bottom: 12px;
          }
          .misc-list {
            list-style: none;
            padding: 0;
          }
          .misc-list li {
            font-size: 13px;
            color: #64748B;
            padding: 4px 0 4px 18px;
            position: relative;
            line-height: 1.5;
          }
          .misc-list li::before {
            content: "✓";
            position: absolute;
            left: 0;
            color: #94A3B8;
            font-size: 12px;
            top: 5px;
          }

          /* ── CTA ── */
          .cta-section {
            margin-top: 32px;
            text-align: center;
            padding-top: 24px;
            border-top: 1px solid #E2E8F0;
          }
          .cta-label {
            font-size: 13px;
            color: #94A3B8;
            margin-bottom: 14px;
          }
          .cta-button {
            display: inline-block;
            background: linear-gradient(135deg, #0F2D5A, #1B5E99);
            color: #FFFFFF;
            text-decoration: none;
            font-size: 14px;
            font-weight: 700;
            letter-spacing: 0.5px;
            padding: 13px 32px;
            border-radius: 8px;
          }

          /* ── Footer ── */
          .footer {
            background: #F8FAFC;
            border: 1px solid #E2E8F0;
            border-top: none;
            border-radius: 0 0 12px 12px;
            padding: 20px 40px;
            text-align: center;
          }
          .footer p {
            font-size: 12px;
            color: #94A3B8;
            line-height: 1.6;
          }

          /* ── Draft badge ── */
          .draft-badge {
            text-align: center;
            margin-bottom: 16px;
          }
          .draft-badge span {
            display: inline-block;
            background: #FEF9C3;
            border: 1px solid #FDE047;
            color: #854D0E;
            font-size: 11px;
            font-weight: 700;
            letter-spacing: 1.5px;
            text-transform: uppercase;
            padding: 4px 14px;
            border-radius: 99px;
          }
        </style>
      </head>
      <body>
        <div class="email-wrapper">

          #{draft ? '<div class="draft-badge"><span>Draft — Review before sending</span></div>' : ''}

          <div class="header">
            <div class="header-product">#{ERB::Util.html_escape(product_name)}</div>
            <div class="header-headline">#{ERB::Util.html_escape(data["subject"])}</div>
            <span class="header-meta">#{date_str}</span>
          </div>

          <div class="preview-bar">
            #{ERB::Util.html_escape(data["preview_text"])}
          </div>

          <div class="body">
            <p class="intro">
              Here's a look at what we've been building for you this week — new capabilities
              designed to help you work smarter, move faster, and make better decisions.
            </p>

            #{sections_html}

            #{misc_html}

            <div class="cta-section">
              <p class="cta-label">Ready to explore what's new?</p>
              <a href="#" class="cta-button">Log in to #{ERB::Util.html_escape(product_name)} →</a>
            </div>
          </div>

          <div class="footer">
            <p>
              You're receiving this because you're a #{ERB::Util.html_escape(product_name)} client.<br>
              Questions? Reply to this email — we'd love to hear from you.
            </p>
          </div>

        </div>
      </body>
      </html>
    HTML
  end
end

namespace :irm do
  desc <<~DESC
    Generate internal engineering update from recent git commits (all commit types, full detail).
    Options:
      DAYS=7                Number of days to look back (default: 7)
      PRODUCT=CapHive       Product name (default: CapHive)
      SEND=true             Send to support@caphive.com via SES after generating
      TO=foo@bar.com        Override recipient (only with SEND=true)
      CREDS_ENV=staging.in  Use a different credentials environment for SMTP (default: current Rails env)
  DESC
  task weekly_email_internal: :environment do
    since_days   = (ENV["DAYS"]    || 7).to_i
    product_name = ENV.fetch("PRODUCT", "CapHive")
    should_send  = ENV["SEND"].to_s.casecmp?("true")
    recipient    = ENV.fetch("TO", WeeklyEmailTask::DEFAULT_RECIPIENT)
    creds_env    = ENV.fetch("CREDS_ENV", Rails.env)

    puts "Scanning commits from the last #{since_days} days (internal report)..."

    git_root = Rails.root.to_s.shellescape
    raw_log  = `git -C #{git_root} log --since="#{since_days} days ago" --pretty=format:"%H|||%s" --no-merges 2>&1`
    commits  = raw_log.split("\n").map(&:strip).reject(&:blank?).filter_map do |line|
      hash, msg = line.split("|||", 2)
      { hash: hash.strip, message: msg.to_s.strip }
    end

    feat_commits  = commits.select { |c| c[:message].match?(/\AFeat:/i) }
    fix_commits   = commits.select { |c| c[:message].match?(/\AFix:/i)  }
    other_commits = commits - feat_commits - fix_commits

    if commits.empty?
      puts "No commits found in the last #{since_days} days. Aborting."
      next
    end

    puts "  #{feat_commits.size} feature(s), #{fix_commits.size} fix(es), #{other_commits.size} other."
    puts "  Fetching app/packs diffs per commit..."

    [feat_commits, fix_commits, other_commits].each do |group|
      group.each do |commit|
        commit[:diff] = `git -C #{git_root} show #{commit[:hash]} -p -- app/packs/ 2>&1`
      end
    end

    puts "Calling Gemini 3 Flash to draft internal report..."

    prompt   = WeeklyEmailTask.build_internal_prompt(feat_commits, fix_commits, other_commits, product_name)
    chat     = RubyLLM.chat(model: "gemini-3-flash-preview", provider: :gemini, assume_model_exists: true)
    raw_text = chat.ask(prompt).content

    json_str = raw_text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    data     = JSON.parse(json_str)

    date_str    = Date.today.strftime("%B %-d, %Y")
    output_path = Rails.root.join("tmp", "weekly_internal_#{Date.today.strftime('%Y-%m-%d')}.html")
    html        = WeeklyEmailTask.render_internal_html(data, product_name, date_str)

    File.write(output_path, html)

    puts ""
    puts "  Title   : #{data['title']}"
    puts "  Areas   : #{data['sections']&.map { |s| s['area'] }&.join(' · ')}"
    puts ""
    puts "Saved to: #{output_path}"

    if should_send
      puts "Resolving SMTP credentials from '#{creds_env}'..."
      smtp_settings = WeeklyEmailTask.smtp_settings_for(creds_env)
      from = smtp_settings.delete(:_from)
      puts "Sending to #{recipient} from #{from} via #{smtp_settings[:address]}..."
      ActionMailer::Base.raise_delivery_errors = true
      SanitizeEmail.unsanitary do
        WeeklyEmailTask::ProductMailer
          .weekly_update(to: recipient, from: from, subject: data["title"], html: html, smtp_settings: smtp_settings)
          .deliver_now
      end
      puts "Sent."
    else
      puts "Opening preview in browser..."
      system("xdg-open #{output_path.to_s.shellescape} &")
      puts "(Run with SEND=true to deliver to #{recipient})"
    end
  end

  desc <<~DESC
    Generate weekly marketing email draft from recent git commits.
    Options:
      DAYS=7                Number of days to look back (default: 7)
      PRODUCT=CapHive       Product name shown in the email (default: CapHive)
      SEND=true             Send to support@caphive.com via SES after generating
      TO=foo@bar.com        Override recipient (only with SEND=true)
      CREDS_ENV=staging.in  Use a different credentials environment for SMTP (default: current Rails env)
  DESC
  task weekly_email: :environment do
    since_days   = (ENV["DAYS"]    || 7).to_i
    product_name = ENV.fetch("PRODUCT", "CapHive")
    should_send  = ENV["SEND"].to_s.casecmp?("true")
    recipient    = ENV.fetch("TO", WeeklyEmailTask::DEFAULT_RECIPIENT)
    creds_env    = ENV.fetch("CREDS_ENV", Rails.env)

    puts "Scanning commits from the last #{since_days} days..."

    git_root = Rails.root.to_s.shellescape
    raw_log  = `git -C #{git_root} log --since="#{since_days} days ago" --pretty=format:"%H|||%s" --no-merges 2>&1`
    commits  = raw_log.split("\n").map(&:strip).reject(&:blank?).filter_map do |line|
      hash, msg = line.split("|||", 2)
      { hash: hash.strip, message: msg.to_s.strip }
    end

    feat_commits = commits.select { |c| c[:message].match?(/\AFeat:/i) }
    fix_commits  = commits.select { |c| c[:message].match?(/\AFix:/i)  }

    if feat_commits.empty? && fix_commits.empty?
      puts "No Feat: or Fix: commits found in the last #{since_days} days. Aborting."
      next
    end

    puts "  #{feat_commits.size} feature(s), #{fix_commits.size} fix(es) found."
    puts "  Fetching app/packs diffs per commit..."

    # Attach the app/packs-only diff to each commit for richer context
    [feat_commits, fix_commits].each do |group|
      group.each do |commit|
        commit[:diff] = `git -C #{git_root} show #{commit[:hash]} -p -- app/packs/ 2>&1`
      end
    end
    puts "Calling Gemini 3 Flash to draft email content..."

    prompt   = WeeklyEmailTask.build_prompt(feat_commits, fix_commits, product_name)
    # assume_model_exists bypasses RubyLLM's bundled model list so we can use
    # models newer than the gem's models.json (e.g. gemini-3-flash-preview)
    chat     = RubyLLM.chat(model: "gemini-3-flash-preview", provider: :gemini, assume_model_exists: true)
    raw_text = chat.ask(prompt).content

    # Gemini may wrap JSON in markdown code fences — strip defensively
    json_str = raw_text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    data     = JSON.parse(json_str)

    date_str    = Date.today.strftime("%B %-d, %Y")
    output_path = Rails.root.join("tmp", "weekly_email_#{Date.today.strftime('%Y-%m-%d')}.html")
    html        = WeeklyEmailTask.render_html(data, product_name, date_str, draft: !should_send)

    File.write(output_path, html)

    puts ""
    puts "  Subject : #{data['subject']}"
    puts "  Sections: #{data['sections']&.map { |s| s['title'] }&.join(' · ')}"
    puts ""
    puts "Saved to: #{output_path}"

    if should_send
      puts "Resolving SMTP credentials from '#{creds_env}'..."
      smtp_settings = WeeklyEmailTask.smtp_settings_for(creds_env)
      from = smtp_settings.delete(:_from)
      puts "Sending to #{recipient} from #{from} via #{smtp_settings[:address]}..."
      # Force errors to surface — dev has raise_delivery_errors=false which swallows SMTP failures silently
      ActionMailer::Base.raise_delivery_errors = true
      # Bypass sanitize_email (which redirects to SANDBOX_EMAILS in development)
      SanitizeEmail.unsanitary do
        WeeklyEmailTask::ProductMailer
          .weekly_update(to: recipient, from: from, subject: data["subject"], html: html, smtp_settings: smtp_settings)
          .deliver_now
      end
      puts "Sent."
    else
      puts "Opening preview in browser..."
      system("xdg-open #{output_path.to_s.shellescape} &")
      puts "(Run with SEND=true to deliver to #{recipient})"
    end
  end
end
