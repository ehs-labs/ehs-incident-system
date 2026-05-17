require "rails_helper"

RSpec.describe "GET /api/v1/dashboard", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  before do
    create(:site_membership, user: investigator, site: site)
    create(:site_membership, user: worker,       site: site)
  end

  def json
    JSON.parse(response.body)
  end

  context "as admin" do
    it "returns all dashboard KPIs scoped to org" do
      create(:incident, organization: organization, site: site, reporter: worker, severity: 1)
      create(:incident, organization: organization, site: site, reporter: worker, severity: 3)

      get "/api/v1/dashboard", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      attrs = json.dig("data", "attributes")
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

    it "ignores incidents from other organizations" do
      other_org = create(:organization)
      other_site = create(:site, organization: other_org)
      create(:incident, organization: other_org, site: other_site,
                       reporter: create(:user, organization: other_org), severity: 1)

      get "/api/v1/dashboard", headers: auth_headers(admin)

      expect(json.dig("data", "attributes", "open_incidents_by_severity").values.sum).to eq(0)
    end
  end

  context "as worker" do
    it "returns only the worker's own incidents" do
      mine  = create(:incident, organization: organization, site: site, reporter: worker, severity: 2)
      _theirs = create(:incident, organization: organization, site: site,
                                  reporter: create(:user, organization: organization), severity: 4)

      get "/api/v1/dashboard", headers: auth_headers(worker)

      expect(response).to have_http_status(:ok)
      buckets = json.dig("data", "attributes", "open_incidents_by_severity")
      expect(buckets["2"]).to eq(1)
      expect(buckets["4"]).to eq(0)
    end
  end

  context "as investigator" do
    it "returns incidents on sites the investigator is a member of" do
      other_site = create(:site, organization: organization)
      create(:incident, organization: organization, site: site,       reporter: worker, severity: 1)
      create(:incident, organization: organization, site: other_site, reporter: worker, severity: 5)

      get "/api/v1/dashboard", headers: auth_headers(investigator)

      buckets = json.dig("data", "attributes", "open_incidents_by_severity")
      expect(buckets["1"]).to eq(1)
      expect(buckets["5"]).to eq(0) # not a member of other_site
    end
  end

  it "returns 401 without a token" do
    get "/api/v1/dashboard"
    expect(response).to have_http_status(:unauthorized)
  end
end
