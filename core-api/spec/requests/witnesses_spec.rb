require "rails_helper"

RSpec.describe "Api::V1::Witnesses", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }

  before do
    create(:site_membership, site: site, user: investigator)
    create(:site_membership, site: site, user: admin)
  end

  describe "GET /api/v1/incidents/:incident_id/witnesses" do
    let!(:witness) { create(:witness, incident: incident) }

    it "lists witnesses for a visible incident" do
      get "/api/v1/incidents/#{incident.id}/witnesses", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).fetch("data")
      expect(data.size).to eq(1)
      expect(data.first["id"]).to eq(witness.id.to_s)
    end

    it "rejects access for users in another org" do
      other_org   = create(:organization)
      other_admin = create(:user, :admin, organization: other_org)

      get "/api/v1/incidents/#{incident.id}/witnesses", headers: auth_headers(other_admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/incidents/:incident_id/witnesses" do
    let(:payload) do
      { witness: { name: "Eyewitness", email: "eye@example.com", phone: "+61", statement: "I saw it." } }
    end

    it "allows the reporter to add a witness to their draft" do
      post "/api/v1/incidents/#{incident.id}/witnesses", params: payload, headers: auth_headers(reporter), as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("data", "attributes", "name")).to eq("Eyewitness")
    end

    it "hides the incident from a worker who is not the reporter" do
      other_worker = create(:user, organization: organization)
      post "/api/v1/incidents/#{incident.id}/witnesses", params: payload, headers: auth_headers(other_worker), as: :json

      # The incident is outside the worker's policy_scope, so set_incident
      # raises RecordNotFound before authorize even runs.
      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when the name is missing" do
      post "/api/v1/incidents/#{incident.id}/witnesses",
           params: { witness: { name: "" } },
           headers: auth_headers(admin),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/witnesses/:id" do
    let!(:witness) { create(:witness, incident: incident, name: "Old") }

    it "lets an admin update the witness" do
      patch "/api/v1/witnesses/#{witness.id}",
            params: { witness: { name: "New" } },
            headers: auth_headers(admin),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(witness.reload.name).to eq("New")
    end

    it "forbids a worker from editing a witness" do
      patch "/api/v1/witnesses/#{witness.id}",
            params: { witness: { name: "New" } },
            headers: auth_headers(reporter),
            as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/witnesses/:id" do
    let!(:witness) { create(:witness, incident: incident) }

    it "lets an investigator delete the witness" do
      delete "/api/v1/witnesses/#{witness.id}", headers: auth_headers(investigator)
      expect(response).to have_http_status(:no_content)
      expect(Witness.where(id: witness.id)).to be_empty
    end

    it "forbids the reporter from deleting the witness" do
      delete "/api/v1/witnesses/#{witness.id}", headers: auth_headers(reporter)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
