require "rails_helper"

RSpec.describe "MeController", type: :request do
  let(:organization) { create(:organization, slug: "acme-co") }
  let(:site)         { create(:site, organization: organization, name: "Plant 1", timezone: "Australia/Sydney") }
  let(:user)         { create(:user, organization: organization, name: "Original Name") }

  before { create(:site_membership, user: user, site: site) }

  def json = JSON.parse(response.body)

  describe "GET /api/v1/me" do
    it "returns the current user's profile" do
      get "/api/v1/me", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      attrs = json.dig("data", "attributes")
      expect(attrs["email"]).to eq(user.email)
      expect(attrs["name"]).to eq("Original Name")
      expect(attrs["role"]).to eq("worker")
      expect(attrs["organization"]).to include("slug" => "acme-co")
      expect(attrs["sites"].first).to include("name" => "Plant 1", "timezone" => "Australia/Sydney")
    end

    it "401s without a token" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/me" do
    it "updates name only" do
      patch "/api/v1/me",
        params: { me: { name: "New Name", email: "hacker@example.com", role: "admin" } },
        headers: auth_headers(user).merge("Content-Type" => "application/json"),
        as: :json

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.name).to eq("New Name")
      expect(user.email).not_to eq("hacker@example.com")
      expect(user.role).to eq("worker")
    end
  end

end
