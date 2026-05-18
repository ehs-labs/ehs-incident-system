require "swagger_helper"

RSpec.describe "Admin Sites API", type: :request do
  let(:organization) { create(:organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/admin/sites" do
    get "List all sites in the organization" do
      tags "admin/sites"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "200", "OK — admin lists sites" do
        before { create(:site, organization: organization, name: "Original") }

        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          expect(data).to be_an(Array)
          expect(data.map { |s| s["id"].to_i }).to be_present
        end
      end

      response "403", "Forbidden — worker cannot list sites" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end

    post "Create a new site" do
      tags "admin/sites"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          site: {
            type: :object,
            required: %w[name timezone],
            properties: {
              name:     { type: :string },
              timezone: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "201", "Created — valid site" do
        let(:body) { { site: { name: "New Plant", timezone: "Australia/Sydney" } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("data", "attributes", "name")).to eq("New Plant")
        end
      end

      response "422", "Unprocessable — invalid timezone" do
        let(:body) { { site: { name: "Bad Plant", timezone: "Not/AZone" } } }
        produces "application/problem+json"
        run_test! do |response|
          expect([422, 422]).to include(response.status)
        end
      end

      response "403", "Forbidden — worker cannot create a site" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }
        let(:body) { { site: { name: "X", timezone: "UTC" } } }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end

  path "/api/v1/admin/sites/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let(:site) { create(:site, organization: organization, name: "Original") }
    let(:id)   { site.id }

    patch "Update a site" do
      tags "admin/sites"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          site: {
            type: :object,
            properties: {
              name:     { type: :string },
              timezone: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }
      let(:body)          { { site: { name: "Renamed" } } }

      response "200", "OK — name updated" do
        run_test! do |response|
          expect(JSON.parse(response.body).dig("data", "attributes", "name")).to eq("Renamed")
        end
      end
    end

    delete "Destroy a site" do
      tags "admin/sites"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "204", "No Content — site deleted" do
        run_test! do |response|
          expect(response.status).to eq(204)
        end
      end
    end
  end
end
