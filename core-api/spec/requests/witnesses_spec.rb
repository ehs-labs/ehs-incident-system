require "swagger_helper"

RSpec.describe "Witnesses API", type: :request do
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

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/incidents/{incident_id}/witnesses" do
    parameter name: :incident_id, in: :path, schema: { type: :integer }, required: true
    let(:incident_id) { incident.id }

    get "List witnesses for an incident" do
      tags "witnesses"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }
      let!(:witness) { create(:witness, incident: incident) }

      response "200", "OK — lists witnesses for a visible incident" do
        run_test! do |response|
          data = JSON.parse(response.body).fetch("data")
          expect(data.size).to eq(1)
          expect(data.first["id"]).to eq(witness.id.to_s)
        end
      end

      response "404", "Not Found — user from another org cannot see the incident" do
        let(:other_org)   { create(:organization) }
        let(:other_admin) { create(:user, :admin, organization: other_org) }
        let(:Authorization) { "Bearer #{jwt_for(other_admin)}" }
        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end

    post "Add a witness to an incident" do
      tags "witnesses"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          witness: {
            type: :object,
            required: ["name"],
            properties: {
              name:      { type: :string },
              email:     { type: :string, format: :email },
              phone:     { type: :string },
              statement: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
      let(:body) { { witness: { name: "Eyewitness", email: "eye@example.com", phone: "+61", statement: "I saw it." } } }

      response "201", "Created — reporter adds a witness to their draft" do
        run_test! do |response|
          expect(JSON.parse(response.body).dig("data", "attributes", "name")).to eq("Eyewitness")
        end
      end

      response "404", "Not Found — non-reporter worker cannot see the incident" do
        let(:other_worker) { create(:user, organization: organization) }
        let(:Authorization) { "Bearer #{jwt_for(other_worker)}" }
        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end

      response "422", "Unprocessable — name is required" do
        let(:body) { { witness: { name: "" } } }
        let(:Authorization) { "Bearer #{jwt_for(admin)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(422)
        end
      end
    end
  end

  path "/api/v1/witnesses/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let!(:witness) { create(:witness, incident: incident) }
    let(:id)       { witness.id }

    patch "Update a witness" do
      tags "witnesses"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          witness: {
            type: :object,
            properties: {
              name:      { type: :string },
              email:     { type: :string, format: :email },
              phone:     { type: :string },
              statement: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }
      let(:body)          { { witness: { name: "New" } } }

      response "200", "OK — admin updates the witness" do
        run_test! do |response|
          expect(witness.reload.name).to eq("New")
        end
      end

      response "403", "Forbidden — worker cannot edit a witness" do
        let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end

    delete "Delete a witness" do
      tags "witnesses"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

      response "204", "No Content — investigator deletes the witness" do
        run_test! do |response|
          expect(Witness.where(id: witness.id)).to be_empty
        end
      end

      response "403", "Forbidden — reporter cannot delete a witness" do
        let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end
end
