require "rails_helper"

RSpec.describe "Admin::SettingsController", type: :request do
  let(:organization) { create(:organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def json = JSON.parse(response.body)

  context "as admin" do
    it "returns empty overrides initially" do
      get "/api/v1/admin/settings", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "attributes", "sla_overrides")).to eq({})
    end

    it "updates the sla overrides and the new value flows into Incident#triage_sla" do
      patch "/api/v1/admin/settings",
        params: { setting: { sla_overrides: { "1" => { "triage_seconds" => 7200 } } } },
        headers: auth_headers(admin),
        as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "attributes", "sla_overrides", "1", "triage_seconds")).to eq(7200)

      site = create(:site, organization: organization)
      reporter = create(:user, organization: organization)
      incident = create(:incident, organization: organization, site: site, reporter: reporter, severity: 1)
      expect(incident.triage_sla.to_i).to eq(7200)
    end
  end

  context "as non-admin" do
    it "rejects worker" do
      get "/api/v1/admin/settings", headers: auth_headers(worker)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
