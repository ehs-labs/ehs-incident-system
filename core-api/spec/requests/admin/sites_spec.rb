require "rails_helper"

RSpec.describe "Admin::SitesController", type: :request do
  let(:organization) { create(:organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def json = JSON.parse(response.body)

  context "as admin" do
    it "creates a site" do
      post "/api/v1/admin/sites",
        params: { site: { name: "New Plant", timezone: "Australia/Sydney" } },
        headers: auth_headers(admin),
        as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "attributes", "name")).to eq("New Plant")
    end

    it "rejects an invalid timezone" do
      post "/api/v1/admin/sites",
        params: { site: { name: "Bad Plant", timezone: "Not/AZone" } },
        headers: auth_headers(admin),
        as: :json
      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    end

    it "lists, updates and destroys" do
      site = create(:site, organization: organization, name: "Original")
      get "/api/v1/admin/sites", headers: auth_headers(admin)
      expect(json["data"].map { |s| s["id"].to_i }).to include(site.id)

      patch "/api/v1/admin/sites/#{site.id}",
        params: { site: { name: "Renamed" } },
        headers: auth_headers(admin),
        as: :json
      expect(json.dig("data", "attributes", "name")).to eq("Renamed")

      delete "/api/v1/admin/sites/#{site.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
    end
  end

  context "as worker" do
    it "rejects index" do
      get "/api/v1/admin/sites", headers: auth_headers(worker)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects create" do
      post "/api/v1/admin/sites",
        params: { site: { name: "X", timezone: "UTC" } },
        headers: auth_headers(worker),
        as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
