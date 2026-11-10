# frozen_string_literal: true

# Settings › Security Events: the firm's security event trail — list, filter, cards, spreadsheet by email
# (OWASP review 2026-11 M11, design card ⑥). Read-only: there is no show, create, update or destroy route (X11).
#
# Modelled on AuditsController (one index, xlsx handed to a job) and styled after capital_calls/_index.
class SecurityEventsController < ApplicationController
  ROWS_PER_PAGE = 25

  # GET /security_events (html) — H29, H30, E38–E40, E45, X6–X8
  # GET /security_events.xlsx    — H31, X9: the same filter, emailed by SecurityEventDownloadJob
  def index
    # X6 / X7 — company admins, support and super only
    authorize SecurityEvent
    @bread_crumbs = { Settings: nil, 'Security Events': nil }
    # The same filter object the download job uses, so both give the same rows
    @filter = SecurityEventFilter.new(filter_params)

    respond_to do |format|
      format.html { load_page }
      format.xlsx { request_download }
    end
  end

  private

  def filter_params
    params.permit(:from, :to, :account, q: SecurityEventFilter::FORM_CONDITIONS).to_h
  end

  # The list, its cards and the pager
  def load_page
    # E39 — say so when the period was shortened
    flash.now[:notice] = "The period was shortened to the last 13 months — the trail keeps nothing older." if @filter.clamped?
    # The tenant filter (policy) first, then the form's conditions
    rows = @filter.apply(policy_scope(SecurityEvent))
    # E40 — the cards count exactly the filtered rows, in one grouped query
    @card_counts = rows.unscope(:order).group(:category, :kind, :outcome).count
    # A Firm column only for those who see more than one firm
    @multi_firm = current_user.has_cached_role?(:super) || current_user.has_cached_role?(:support)
    # The people (and, for the Firm column, the firms) of the page in one query each — never per row
    preloads = %i[user actor impersonator]
    preloads << :entity if @multi_firm
    @pagy, @security_events = pagy(rows.order(occurred_at: :desc, id: :desc).includes(*preloads), limit: ROWS_PER_PAGE)
    # Whose user pages the viewer may open: nil = every firm (super); else these firms only. Worked out once, so
    # the rows never ask the policy one by one
    @linkable_entity_ids = linkable_entity_ids
  end

  # H31 — emailed, never built in the request (13 months of a firm can be thousands of rows)
  def request_download
    # X9 — the job re-applies SecurityEventPolicy::Scope with the reloaded user, so nothing is scoped here
    skip_policy_scope
    SecurityEventDownloadJob.perform_later(@filter.to_params.deep_stringify_keys, user_id: current_user.id)
    redirect_to security_events_path(@filter.to_params), notice: "Your request is being processed. You will receive an email shortly."
  end

  def linkable_entity_ids
    return nil if current_user.has_cached_role?(:super)
    return SecurityEventPolicy.supported_entity_ids(current_user).pluck(:entity_id) if current_user.has_cached_role?(:support)

    [current_user.entity_id]
  end
end
