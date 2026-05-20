require "swagger_helper"

RSpec.describe "Incident Versions API", type: :request, versioning: true do
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
    PaperTrail.request.whodunnit = nil
    inc
  end

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/incidents/{incident_id}/versions" do
    parameter name: :incident_id, in: :path, schema: { type: :integer }, required: true
    let(:incident_id) { incident.id }

    get "Audit trail for an incident" do
      tags "incident_versions"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }

      response "200", "OK — full audit trail in JSON:API shape" do
        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          expect(data.size).to eq(4) # create + submit + update + triage
          first = data.first
          expect(first["type"]).to eq("version")
          expect(first["attributes"].keys).to include("event", "created_at", "whodunnit_user", "changes")
          expect(first["attributes"]["event"]).to eq("create")
          expect(first["attributes"]["whodunnit_user"]).to include(
            "id" => reporter.id, "email" => reporter.email, "name" => reporter.name
          )
        end
      end

      response "200", "OK — whodunnit_user is resolved per-version across different users" do
        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          triage_row = data.find { |r| r["attributes"]["changes"]["state"] == %w[submitted investigating] }
          expect(triage_row).not_to be_nil
          expect(triage_row["attributes"]["whodunnit_user"]).to include("id" => investigator.id)
        end
      end

      response "404", "Not Found — Pundit scope hides incident from unrelated worker" do
        let(:Authorization) { "Bearer #{jwt_for(other_worker)}" }
        run_test! do |response|
          expect(response.status).to eq(404)
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
