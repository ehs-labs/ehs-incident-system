require "rails_helper"

RSpec.describe "Admin::UsersController", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def json = JSON.parse(response.body)

  context "as admin" do
    it "lists users in own organization" do
      other_org_user = create(:user, organization: create(:organization))
      _peer = create(:user, organization: organization)

      get "/api/v1/admin/users", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      ids = json["data"].map { |u| u["id"].to_i }
      expect(ids).to include(admin.id)
      expect(ids).not_to include(other_org_user.id)
    end

    it "filters by role" do
      worker; investigator
      get "/api/v1/admin/users", params: { role: "investigator" }, headers: auth_headers(admin)

      roles = json["data"].map { |u| u.dig("attributes", "role") }
      expect(roles.uniq).to eq(["investigator"])
    end

    it "filters by q (email/name)" do
      target = create(:user, organization: organization, name: "Findable Person", email: "findable@example.com")

      get "/api/v1/admin/users", params: { q: "findable" }, headers: auth_headers(admin)

      ids = json["data"].map { |u| u["id"].to_i }
      expect(ids).to include(target.id)
    end

    it "invites a user via devise_invitable and assigns sites" do
      expect {
        post "/api/v1/admin/users/invite",
          params: { user: { email: "newhire@example.com", name: "New Hire", role: "worker", site_ids: [site.id] } },
          headers: auth_headers(admin),
          as: :json
      }.to change(ActionMailer::Base.deliveries, :count).by(1)

      expect(response).to have_http_status(:created)
      invited = User.find_by(email: "newhire@example.com")
      expect(invited.invitation_token).to be_present
      expect(invited.sites).to include(site)
    end

    it "locks and unlocks a user" do
      post "/api/v1/admin/users/#{worker.id}/lock", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(worker.reload.access_locked?).to be(true)

      post "/api/v1/admin/users/#{worker.id}/unlock", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(worker.reload.access_locked?).to be(false)
    end

    it "soft-deletes a user" do
      delete "/api/v1/admin/users/#{worker.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(worker.reload.deleted_at).to be_present
    end
  end

  context "as non-admin" do
    it "rejects worker from listing" do
      get "/api/v1/admin/users", headers: auth_headers(worker)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects investigator from invite" do
      post "/api/v1/admin/users/invite",
        params: { user: { email: "x@example.com", name: "x", role: "worker" } },
        headers: auth_headers(investigator),
        as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects worker from lock" do
      post "/api/v1/admin/users/#{investigator.id}/lock", headers: auth_headers(worker)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
