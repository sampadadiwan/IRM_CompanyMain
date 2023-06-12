class KpiPolicyBase < ApplicationPolicy
  def permissioned_employee?(perm = nil)
    if user.entity_id == record.entity_id
      if user.has_cached_role?(:company_admin)
        true
      else
        kpi_report_id = record.instance_of?(KpiReport) ? record.id : record.kpi_report_id
        @kpi_report ||= KpiReport.for_employee(user).includes(:access_rights).where("kpi_reports.id=?", kpi_report_id).first
        if perm
          @kpi_report.present? && @kpi_report.access_rights[0].permissions.set?(perm)
        else
          @kpi_report.present?
        end
      end
    else
      false
    end
  end

  def permissioned_investor?
    if user.entity_id == record.entity_id
      false
    else
      @pi_record ||= record.class.for_investor(user).where("#{record.class.table_name}.id=?", record.id)
      @pi_record.present?
    end
  end
end
