module Api
  module V1
    class DashboardController < BaseController
      # GET /api/v1/dashboard
      def show
        scope = policy_scope(::Incident)

        attributes = {
          open_incidents_by_severity:    open_incidents_by_severity(scope),
          incidents_by_state:            incidents_by_state(scope),
          overdue_corrective_actions_count: overdue_corrective_actions_count(scope),
          last_30_day_incidents_trend:   last_30_day_incidents_trend(scope),
          avg_time_to_close_seconds:     avg_time_to_close_seconds(scope),
          sla_compliance:                sla_compliance(scope)
        }

        render json: { data: { type: "dashboard", attributes: attributes } }
      end

      private

      def open_incidents_by_severity(scope)
        counts = scope.open.group(:severity).count
        (1..5).each_with_object({}) { |sev, h| h[sev.to_s] = counts[sev].to_i }
      end

      def incidents_by_state(scope)
        scope.group(:state).count
      end

      def overdue_corrective_actions_count(scope)
        return 0 unless ActiveRecord::Base.connection.data_source_exists?("corrective_actions")

        sql = <<~SQL
          SELECT COUNT(*) FROM corrective_actions ca
          INNER JOIN incidents i ON i.id = ca.incident_id
          WHERE i.id IN (#{scope.select(:id).to_sql})
            AND ca.state IN ('open', 'in_progress')
            AND ca.due_date < :now
        SQL
        ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.sanitize_sql([sql, { now: Time.current }])
        ).rows.flatten.first.to_i
      rescue ActiveRecord::StatementInvalid
        0
      end

      def last_30_day_incidents_trend(scope)
        tz_name = dashboard_timezone
        # Bucket occurred_at by date in the chosen tz; SQL aggregate avoids N+1.
        rows = scope
          .where("occurred_at >= ?", 30.days.ago.beginning_of_day)
          .group(Arel.sql("DATE(occurred_at AT TIME ZONE 'UTC' AT TIME ZONE #{ActiveRecord::Base.connection.quote(tz_name)})"))
          .count

        # Dense fill the last 30 days.
        today = Time.current.in_time_zone(tz_name).to_date
        (29.downto(0)).map do |offset|
          date = today - offset
          { date: date.iso8601, count: rows[date].to_i }
        end
      end

      def avg_time_to_close_seconds(scope)
        result = scope
          .where.not(closed_at: nil)
          .where(closed_at: 90.days.ago..)
          .where.not(submitted_at: nil)
          .pick(Arel.sql("AVG(EXTRACT(EPOCH FROM (closed_at - submitted_at)))"))
        return nil if result.nil?
        result.to_f
      end

      def sla_compliance(scope)
        windows = { "S1_S2" => [1, 2], "S3" => [3], "S4_S5" => [4, 5] }

        # Triage occurred = triaged_at present. SLA met if triaged_at - submitted_at <= sla.
        # Use Incident#triage_sla for per-org overrides — must iterate, but only over the
        # small set of submitted incidents per bucket.
        windows.transform_values do |severities|
          subset = scope.where(severity: severities)
                        .where.not(submitted_at: nil)
                        .where.not(triaged_at: nil)
          total = subset.count
          next "n/a" if total.zero?

          met = subset.find_each.count do |incident|
            (incident.triaged_at - incident.submitted_at) <= incident.triage_sla
          end
          "#{((met.to_f / total) * 100).round}%"
        end
      end

      def dashboard_timezone
        # Organization has no default_timezone column yet; pick any of the org's site
        # timezones, else UTC. Cheap single query.
        ::Site.where(organization_id: current_user.organization_id).order(:created_at).limit(1).pick(:timezone) || "UTC"
      end
    end
  end
end
