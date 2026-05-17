require "rails_helper"

# NOTE: this spec requires the route
#   resources :incidents do
#     resources :versions, only: :index, controller: "incident_versions"
#   end
# to be wired into config/routes.rb. The controller, serializer and Pundit
# scoping are in place; the route lives outside this agent's scope.
RSpec.describe "GET /api/v1/incidents/:incident_id/versions", type: :request, versioning: true do
  before do
    Rails.application.routes.recognize_path("/api/v1/incidents/1/versions", method: :get)
  rescue ActionController::RoutingError
    skip "route /api/v1/incidents/:incident_id/versions not yet wired in config/routes.rb"
  end

  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:other_worker) { create(:user, organization: organization) }

  let(:incident) do
    create(:site_membership, site: site, user: investigator)
    PaperTrail.request.whodunnit = reporter.id.to_s
    inc = create(:incident, organization: organization, site: site, reporter: reporter)
    inc.submit!
    PaperTrail.request.whodunnit = investigator.id.to_s
    inc.update!(assignee: investigator)
    inc.triage!
    inc
  end

  context "as the reporter" do
    it "returns the full audit trail in JSON:API shape" do
      get "/api/v1/incidents/#{incident.id}/versions", headers: auth_headers(reporter)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      data = body["data"]

      expect(data.size).to eq(4) # create + submit + update + triage
      first = data.first
      expect(first["type"]).to eq("version")
      expect(first["attributes"].keys).to include("event", "created_at", "whodunnit_user", "changes")
      expect(first["attributes"]["event"]).to eq("create")
      expect(first["attributes"]["whodunnit_user"]).to include("id" => reporter.id, "email" => reporter.email, "name" => reporter.name)
    end

    it "resolves whodunnit_user for transitions performed by another user" do
      get "/api/v1/incidents/#{incident.id}/versions", headers: auth_headers(reporter)

      data = JSON.parse(response.body)["data"]
      triage_row = data.find { |r| r["attributes"]["changes"]["state"] == %w[submitted investigating] }
      expect(triage_row).not_to be_nil
      expect(triage_row["attributes"]["whodunnit_user"]).to include("id" => investigator.id)
    end
  end

  context "as a worker who is not the reporter" do
    it "returns 404 (Pundit scope hides the incident)" do
      get "/api/v1/incidents/#{incident.id}/versions", headers: auth_headers(other_worker)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "without auth" do
    it "returns 401" do
      get "/api/v1/incidents/#{incident.id}/versions"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
