# frozen_string_literal: true

require 'action_mailer'

module CucumberDashboard
  # Sends real SMTP email notifications for parallel Cucumber runs.
  # Overrides Rails development letter_opener so emails are actually delivered.
  #
  # Configure via environment variables:
  #   CUCUMBER_SMTP_ADDRESS  (default: smtp.gmail.com)
  #   CUCUMBER_SMTP_PORT     (default: 587)
  #   CUCUMBER_SMTP_USER     (required — your email)
  #   CUCUMBER_SMTP_PASSWORD  (required — app password)
  #   CUCUMBER_SMTP_FROM     (default: CUCUMBER_SMTP_USER)
  class CompletionMailer < ActionMailer::Base
    self.delivery_method = :smtp
    self.smtp_settings = {
      address: ENV.fetch('CUCUMBER_SMTP_ADDRESS', 'smtp.gmail.com'),
      port: ENV.fetch('CUCUMBER_SMTP_PORT', 587).to_i,
      user_name: ENV['CUCUMBER_SMTP_USER'],
      password: ENV['CUCUMBER_SMTP_PASSWORD'],
      authentication: 'plain',
      enable_starttls_auto: true
    }

    default from: -> { ENV.fetch('CUCUMBER_SMTP_FROM', ENV['CUCUMBER_SMTP_USER'] || 'cucumber-dashboard@caphive.com') }

    def run_started(to, config)
      @workers = config['workers'] || 4
      @feature_path = config['feature_path'] || 'features/'
      @total_scenarios = config['total_scenarios'] || 0
      @started_at = config['started_at'] || Time.now.to_s

      mail(to: to, subject: "Cucumber Run Started — #{@workers} workers, #{@total_scenarios} scenarios") do |format|
        format.html { render inline: start_html }
        format.text { render inline: start_text }
      end
    end

    def run_complete(to, summary)
      @passed = summary['passed'] || 0
      @failed = summary['failed'] || 0
      @skipped = summary['skipped'] || 0
      @total = @passed + @failed + @skipped
      @duration = summary['duration'] || '—'
      @failures = summary['failures'] || []

      status = @failed > 0 ? "#{@failed} FAILED" : 'ALL PASSED'

      mail(to: to, subject: "Cucumber Run Complete — #{status} (#{@total} scenarios, #{@duration})") do |format|
        format.html { render inline: completion_html }
        format.text { render inline: completion_text }
      end
    end

    def scenario_failed(to, failure)
      @feature = failure['feature'] || ''
      @scenario = failure['scenario'] || ''
      @line = failure['line'] || ''
      @error = failure['error'] || ''
      @worker = failure['worker'] || ''
      @location = "#{@feature}:#{@line}"

      mail(to: to, subject: "FAILED — #{@scenario} (#{short_path(@feature)}:#{@line})") do |format|
        format.html { render inline: failure_html }
        format.text { render inline: failure_text }
      end
    end

    private

    def short_path(p)
      p.to_s.sub(%r{^features/}, '').sub(/\.feature$/, '')
    end

    def start_html
      <<~HTML
        <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: #f0f4ff; border: 1px solid #c8d6f0; border-radius: 6px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 11px; color: #4a6fa5; text-transform: uppercase; font-weight: 600; margin-bottom: 4px;">Run Started</div>
            <div style="font-size: 20px; font-weight: 700; color: #1a1a2e; margin-bottom: 12px;">Cucumber Parallel Run</div>

            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 8px 12px; background: #fff; border: 1px solid #e0e4ea; text-align: center;">
                  <div style="font-size: 10px; color: #888; text-transform: uppercase;">Workers</div>
                  <div style="font-size: 22px; font-weight: 700; color: #4a6fa5;"><%= @workers %></div>
                </td>
                <td style="padding: 8px 12px; background: #fff; border: 1px solid #e0e4ea; text-align: center;">
                  <div style="font-size: 10px; color: #888; text-transform: uppercase;">Scenarios</div>
                  <div style="font-size: 22px; font-weight: 700; color: #4a6fa5;"><%= @total_scenarios %></div>
                </td>
              </tr>
            </table>

            <div style="margin-top: 12px; font-family: monospace; font-size: 12px; color: #555;">
              Features: <strong><%= @feature_path %></strong>
            </div>
          </div>

          <p style="font-size: 12px; color: #999;">Sent by Cucumber Dashboard</p>
        </div>
      HTML
    end

    def start_text
      <<~TEXT
        Cucumber Parallel Run Started
        =============================
        Workers:    <%= @workers %>
        Scenarios:  <%= @total_scenarios %>
        Features:   <%= @feature_path %>
        Started at: <%= @started_at %>
      TEXT
    end

    def completion_html
      <<~HTML
        <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <h2 style="margin: 0 0 16px;">Cucumber Parallel Run Complete</h2>

          <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
            <tr>
              <td style="padding: 12px; background: #f0faf9; border: 1px solid #d0e8e6; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Passed</div>
                <div style="font-size: 24px; font-weight: 700; color: #1a9e92;"><%= @passed %></div>
              </td>
              <td style="padding: 12px; background: #fdf2f2; border: 1px solid #f0d0d0; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Failed</div>
                <div style="font-size: 24px; font-weight: 700; color: #c5303d;"><%= @failed %></div>
              </td>
              <td style="padding: 12px; background: #f5f5f5; border: 1px solid #ddd; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Skipped</div>
                <div style="font-size: 24px; font-weight: 700; color: #888;"><%= @skipped %></div>
              </td>
              <td style="padding: 12px; background: #f5f5f5; border: 1px solid #ddd; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Duration</div>
                <div style="font-size: 24px; font-weight: 700;"><%= @duration %></div>
              </td>
            </tr>
          </table>

          <% if @failures.any? %>
            <h3 style="color: #c5303d; margin: 0 0 8px;">Failed Scenarios</h3>
            <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
              <% @failures.each do |f| %>
                <tr style="border-bottom: 1px solid #eee;">
                  <td style="padding: 6px 8px; font-family: monospace; font-weight: 600;"><%= f['location'] %></td>
                  <td style="padding: 6px 8px; color: #555;"><%= f['scenario'] %></td>
                  <td style="padding: 6px 8px; color: #555; font-size: 11px;">W<%= f['worker'] %></td>
                </tr>
                <% if f['error'] %>
                  <tr style="border-bottom: 1px solid #eee;">
                    <td colspan="3" style="padding: 2px 8px 6px; font-family: monospace; font-size: 11px; color: #c5303d;"><%= f['error'] %></td>
                  </tr>
                <% end %>
              <% end %>
            </table>
          <% end %>

          <p style="margin-top: 20px; font-size: 12px; color: #999;">Sent by Cucumber Dashboard</p>
        </div>
      HTML
    end

    def completion_text
      <<~TEXT
        Cucumber Parallel Run Complete
        ==============================
        Passed:  <%= @passed %>
        Failed:  <%= @failed %>
        Skipped: <%= @skipped %>
        Duration: <%= @duration %>

        <% if @failures.any? %>
        Failed Scenarios:
        <% @failures.each do |f| %>
        - <%= f['location'] %> — <%= f['scenario'] %> (W<%= f['worker'] %>)
          <% if f['error'] %><%= f['error'] %><% end %>
        <% end %>
        <% end %>
      TEXT
    end

    def failure_html
      <<~HTML
        <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: #fdf2f2; border: 1px solid #f0d0d0; border-radius: 6px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 11px; color: #c5303d; text-transform: uppercase; font-weight: 600; margin-bottom: 4px;">Scenario Failed</div>
            <div style="font-size: 16px; font-weight: 700; color: #1a1a2e; margin-bottom: 8px;"><%= @scenario %></div>
            <div style="font-family: monospace; font-size: 13px; color: #555; margin-bottom: 4px;"><%= @location %></div>
            <div style="font-size: 12px; color: #888;">Worker <%= @worker %></div>
          </div>

          <% if @error.present? %>
            <div style="background: #f9f9f9; border: 1px solid #eee; border-radius: 4px; padding: 12px; font-family: monospace; font-size: 12px; color: #c5303d; word-break: break-word;">
              <%= @error %>
            </div>
          <% end %>

          <p style="margin-top: 16px; font-size: 12px; color: #999;">Sent by Cucumber Dashboard</p>
        </div>
      HTML
    end

    def failure_text
      <<~TEXT
        SCENARIO FAILED
        ===============
        Scenario: <%= @scenario %>
        Location: <%= @location %>
        Worker:   <%= @worker %>

        <% if @error.present? %>
        Error:
        <%= @error %>
        <% end %>
      TEXT
    end
  end
end
