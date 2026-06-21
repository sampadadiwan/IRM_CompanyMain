# frozen_string_literal: true

# Shared HTML building blocks for all support agent emails.
# Include this in any mailer that sends agent-related emails.
#
# Usage in a mailer:   helper SupportAgentEmailHelper
# Usage in a template: <%= sa_banner(title: "Cash Flow", label: "All Clear", tone: :success) %>
module SupportAgentEmailHelper
  # ── Colour palette ──────────────────────────────────────────────────────
  SA_COLORS = {
    success: { text: "#2e7d32", bg: "#e8f5e9", border: "#2e7d32" },
    warning: { text: "#e65100", bg: "#fff3e0", border: "#fb8c00" },
    danger:  { text: "#c62828", bg: "#ffebee", border: "#ef9a9a" },
    info:    { text: "#1565c0", bg: "#e3f2fd", border: "#90caf9" },
    muted:   { text: "#757575", bg: "#f5f5f5", border: "#bdbdbd" }
  }.freeze

  # Derive a tone from a free-form status string
  def sa_tone_for(status)
    case status.to_s
    when "pass", "success", "surplus", "ready", "complete", "on_track", "fresh" then :success
    when "fail", "failure", "shortfall", "blocked", "failed", "needs_attention"  then :danger
    when "watch", "warning", "partial", "stale"                                  then :warning
    else :muted
    end
  end

  # ── Banner ───────────────────────────────────────────────────────────────
  # Large coloured header block at the top of the email.
  # title:    small uppercase label above the main label
  # label:    large bold display text (e.g. "All Clear", "100%")
  # subtitle: small text below the label
  # tone:     :success | :warning | :danger | :info | :muted
  def sa_banner(title:, label: nil, subtitle: nil, tone: :muted)
    c = SA_COLORS[tone]
    parts = []
    parts << %(<div style="font-size:11px;font-weight:700;color:#{c[:text]};text-transform:uppercase;letter-spacing:1px;margin-bottom:4px">#{h title}</div>)
    parts << %(<div style="font-size:28px;font-weight:700;color:#{c[:text]};line-height:1">#{h label}</div>) if label
    parts << %(<div style="font-size:12px;color:#555;margin-top:6px">#{subtitle}</div>) if subtitle
    wrap = <<~HTML
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:28px">
        <tr><td style="background:#{c[:bg]};border-left:4px solid #{c[:text]};border-radius:4px;padding:16px 20px">
          #{parts.join}
        </td></tr>
      </table>
    HTML
    wrap.html_safe
  end

  # ── Status badge / pill ──────────────────────────────────────────────────
  def sa_badge(label:, tone: :muted)
    c = SA_COLORS[tone]
    %(<span style="background:#{c[:bg]};color:#{c[:text]};padding:3px 9px;border-radius:12px;font-size:11px;font-weight:700;white-space:nowrap">#{h label}</span>).html_safe
  end

  # ── Section heading ──────────────────────────────────────────────────────
  # Bold title with an optional right-aligned "Action →" link.
  def sa_section(title:, link_text: nil, link_url: nil, top_margin: true)
    link_html = link_text && link_url ? %(<a href="#{link_url}" style="font-size:12px;color:#1565c0;text-decoration:none;font-weight:600">#{h link_text} &rarr;</a>) : ""
    mt = top_margin ? "margin-top:28px;" : ""
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="#{mt}margin-bottom:10px">
        <tr><td style="padding-bottom:6px;border-bottom:1px solid #e0e0e0">
          <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
            <tr>
              <td style="font-size:14px;font-weight:700;color:#333">#{h title}</td>
              <td style="text-align:right">#{link_html}</td>
            </tr>
          </table>
        </td></tr>
      </table>
    HTML
  end

  # ── Callout / alert box ──────────────────────────────────────────────────
  # Left-bordered info / warning / error block.
  # body may contain pre-escaped HTML (mark it html_safe before passing).
  def sa_callout(body:, tone: :info, heading: nil)
    c = SA_COLORS[tone]
    heading_html = heading ? %(<div style="font-size:12px;font-weight:700;color:#{c[:text]};margin-bottom:6px">#{h heading}</div>) : ""
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:16px">
        <tr><td style="padding:12px 14px;background:#{c[:bg]};border-left:3px solid #{c[:border]};border-radius:2px">
          #{heading_html}
          <span style="font-size:12px;color:#555;line-height:1.6">#{body}</span>
        </td></tr>
      </table>
    HTML
  end

  # ── Table helpers ────────────────────────────────────────────────────────
  # sa_table_header("Fund", "Status", ["Net Position", align: :right]) → thead HTML
  def sa_th(*cols)
    cells = cols.map do |col|
      text, align = col.is_a?(Array) ? [col[0], col[1]&.dig(:align)] : [col, :left]
      %(<th style="padding:9px 12px;text-align:#{align || :left};border:1px solid #e0e0e0;font-size:11px;font-weight:700;color:#555;text-transform:uppercase;letter-spacing:0.5px">#{h text}</th>)
    end
    %(<thead><tr style="background:#f5f5f5">#{cells.join}</tr></thead>).html_safe
  end

  def sa_td(text, align: :left, color: nil, bold: false, nowrap: false)
    styles = ["padding:9px 12px", "border:1px solid #e0e0e0", "text-align:#{align}"]
    styles << "color:#{color}" if color
    styles << "font-weight:700" if bold
    styles << "white-space:nowrap" if nowrap
    %(<td style="#{styles.join(';')}">#{text}</td>).html_safe
  end

  # Key-value detail table (two-column)
  def sa_kv_table(rows:)
    cells = rows.map do |label, value, opts|
      tone  = opts&.dig(:tone)
      color = tone ? SA_COLORS[tone][:text] : nil
      bold  = opts&.dig(:bold)
      border_style = bold ? "border-top:2px solid #333;" : ""
      <<~ROW
        <tr style="#{bold ? 'font-weight:700;' : ''}#{border_style}">
          <td style="padding:7px 12px;border:1px solid #e0e0e0;color:#555;#{bold ? 'font-weight:700;' : ''}">#{h label.to_s}</td>
          <td style="padding:7px 12px;border:1px solid #e0e0e0;text-align:right;#{color ? "color:#{color};" : ''}#{bold ? 'font-weight:700;' : ''}">#{value}</td>
        </tr>
      ROW
    end
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;margin-bottom:8px">
        #{cells.join}
      </table>
    HTML
  end

  # ── CTA button ───────────────────────────────────────────────────────────
  def sa_cta(label:, url:)
    <<~HTML.html_safe
      <table role="presentation" class="btn btn-outline-primary" style="margin-top:28px">
        <tbody><tr><td>
          <table role="presentation" border="0" cellpadding="0" cellspacing="0">
            <tbody><tr><td>
              <a href="#{url}" target="_blank">#{h label}</a>
            </td></tr></tbody>
          </table>
        </td></tr></tbody>
      </table>
    HTML
  end

  # ── Footer ────────────────────────────────────────────────────────────────
  def sa_footer(text)
    %(<p style="font-size:11px;color:#aaa;margin-top:36px;padding-top:16px;border-top:1px solid #eee;line-height:1.5">#{text}</p>).html_safe
  end

  # ── Intro paragraph ───────────────────────────────────────────────────────
  def sa_intro(text)
    %(<p style="margin:0 0 20px;font-size:14px;line-height:1.6;color:#334155;">#{text}</p>).html_safe
  end
end
