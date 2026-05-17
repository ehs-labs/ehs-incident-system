require "rails_helper"

RSpec.describe "Api::V1::Comments", type: :request do
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

  describe "GET /api/v1/incidents/:incident_id/comments" do
    let!(:comment) { create(:comment, incident: incident, author: investigator) }

    it "lists comments on the incident" do
      get "/api/v1/incidents/#{incident.id}/comments", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).fetch("data")
      expect(data.size).to eq(1)
      expect(data.first.dig("attributes", "body")).to eq(comment.body)
    end
  end

  describe "POST /api/v1/incidents/:incident_id/comments" do
    let(:payload) { { comment: { body: "First comment" } } }

    it "sets author_id from the current user, ignoring any param" do
      post "/api/v1/incidents/#{incident.id}/comments",
           params: payload.merge(comment: payload[:comment].merge(author_id: admin.id)),
           headers: auth_headers(reporter), as: :json

      expect(response).to have_http_status(:created)
      created = Comment.last
      expect(created.author_id).to eq(reporter.id)
      expect(created.body).to eq("First comment")
    end

    it "hides the incident from unrelated workers" do
      other_worker = create(:user, organization: organization)
      post "/api/v1/incidents/#{incident.id}/comments", params: payload,
           headers: auth_headers(other_worker), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "rejects empty body" do
      post "/api/v1/incidents/#{incident.id}/comments",
           params: { comment: { body: "" } },
           headers: auth_headers(reporter), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/comments/:id" do
    let!(:own_comment) { create(:comment, incident: incident, author: reporter, body: "old") }

    it "lets the author update their own comment" do
      patch "/api/v1/comments/#{own_comment.id}",
            params: { comment: { body: "new" } },
            headers: auth_headers(reporter), as: :json

      expect(response).to have_http_status(:ok)
      expect(own_comment.reload.body).to eq("new")
    end

    it "hides the comment from another unrelated worker" do
      other_worker = create(:user, organization: organization)
      patch "/api/v1/comments/#{own_comment.id}",
            params: { comment: { body: "new" } },
            headers: auth_headers(other_worker), as: :json

      # Comment is on an incident outside the worker's scope, so the lookup
      # returns 404 before the policy denies the edit.
      expect(response).to have_http_status(:not_found)
    end

    it "lets an admin edit any comment" do
      patch "/api/v1/comments/#{own_comment.id}",
            params: { comment: { body: "edited by admin" } },
            headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(own_comment.reload.body).to eq("edited by admin")
    end
  end

  describe "DELETE /api/v1/comments/:id" do
    let!(:comment) { create(:comment, incident: incident, author: investigator) }

    it "lets the author delete their own comment" do
      delete "/api/v1/comments/#{comment.id}", headers: auth_headers(investigator)
      expect(response).to have_http_status(:no_content)
    end
  end
end
