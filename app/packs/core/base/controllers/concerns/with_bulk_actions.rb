module WithBulkActions
  extend ActiveSupport::Concern

  # This is a common action for all models which have filters. Bulk actions can be applied to filtered results. A Job "#{controller_name}BulkActionJob", needs to be defined, which will be passed the ids of the filtered results. and the bulk action to perform on them. Note that the controller must implement a fetch_rows method which returns the filtered results.
  def bulk_actions
    # Here we get a ransack search
    rows = fetch_rows

    # and a bulk action to perform on the results
    bulk_action_job = if params[:bulk_action_job_prefix].blank?
                        # The specific bulk action job is passed as a parameter
                        "#{params[:bulk_action_job_prefix]}_#{controller_name}_bulk_action_job".classify.constantize
                      else
                        # The Default bulk action job is the controller name suffixed with BulkActionJob
                        "#{controller_name}_bulk_action_job".classify.constantize
                      end

    # G20 (client onboarding): a filter or include that joins a has_many (e.g. remittance payments)
    # repeats a record's id once per joined row, so the API count and the job's "completed for N records"
    # counted payments, not remittances. Dedup in SQL; the order is dropped because MySQL rejects
    # DISTINCT with an ORDER BY on a column that is not selected.
    # A paged list (fund units on the website) must keep its order, or the page would hold other
    # rows: there the ids are bounded by the page size, so they are deduped after the pluck
    ids = if rows.limit_value || rows.offset_value
            rows.pluck(:id).uniq
          else
            rows.unscope(:order).distinct.pluck(:id)
          end
    bulk_action_job.perform_later(ids, current_user.id, params[:bulk_action], params: params.to_unsafe_h)

    # P9 (funds-json-api-hardening H30): a bearer-token caller gets a JSON 202 it can read, not a 302 to
    # an HTML page; the website keeps its redirect
    return render(json: { status: "queued", bulk_action: params[:bulk_action], count: ids.size }, status: :accepted) if api_request?

    # and redirect back to the page we came from
    redirect_path = request.referer || root_path
    redirect_to redirect_path, notice: "Bulk Action started, please check back in a few mins."
  end
end
