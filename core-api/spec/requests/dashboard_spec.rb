require "swagger_helper"

RSpec.describe "Dashboard API", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  before do
    create(:site_membership, user: investigator, site: site)
    create(:site_membership, user: worker,       site: site)
  end

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/dashboard" do
    get "Summary stats for current user" do
      tags "dashboard"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "200", "OK — all KPIs scoped to organization (admin view)" do
        before do
          create(:incident, organization: organization, site: site, reporter: worker, severity: 1)
          create(:incident, organization: organization, site: site, reporter: worker, severity: 3)
        end

        run_test! do |response|
          attrs = JSON.parse(response.body).dig("data", "attributes")
          expect(attrs).to include(
            "open_incidents_by_severity",
            "incidents_by_state",
            "overdue_corrective_actions_count",
            "last_30_day_incidents_trend",
            "avg_time_to_close_seconds",
            "sla_compliance"
          )
          expect(attrs["open_incidents_by_severity"]).to eq("1" => 1, "2" => 0, "3" => 1, "4" => 0, "5" => 0)
          expect(attrs["last_30_day_incidents_trend"].length).to eq(30)
        end
      end

      response "200", "OK — incidents from other organizations are excluded" do
        before do
          other_org  = create(:organization)
          other_site = create(:site, organization: other_org)
          create(:incident, organization: other_org, site: other_site,
                            reporter: create(:user, organization: other_org), severity: 1)
        end

        run_test! do |response|
          attrs = JSON.parse(response.body).dig("data", "attributes")
          expect(attrs["open_incidents_by_severity"].values.sum).to eq(0)
        end
      end

      response "200", "OK — worker sees only their own incidents" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }

        before do
          create(:incident, organization: organization, site: site, reporter: worker, severity: 2)
          create(:incident, organization: organization, site: site,
                            reporter: create(:user, organization: organization), severity: 4)
        end

        run_test! do |response|
          buckets = JSON.parse(response.body).dig("data", "attributes", "open_incidents_by_severity")
          expect(buckets["2"]).to eq(1)
          expect(buckets["4"]).to eq(0)
        end
      end

      response "200", "OK — investigator sees incidents on their sites only" do
        let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

        before do
          other_site = create(:site, organization: organization)
          create(:incident, organization: organization, site: site,       reporter: worker, severity: 1)
          create(:incident, organization: organization, site: other_site, reporter: worker, severity: 5)
        end

        run_test! do |response|
          buckets = JSON.parse(response.body).dig("data", "attributes", "open_incidents_by_severity")
          expect(buckets["1"]).to eq(1)
          expect(buckets["5"]).to eq(0)
        end
      end

      response "401", "Unauthorized — no token" do
        let(:Authorization) { "" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(401)
        end
      end
    end
  end
end
