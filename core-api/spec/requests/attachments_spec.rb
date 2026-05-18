require "rails_helper"

RSpec.describe "Api::V1::Attachments", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }

  let(:fixture_path) { Rails.root.join("spec/fixtures/files/sample.png") }
  let(:upload) do
    Rack::Test::UploadedFile.new(fixture_path.to_s, "image/png")
  end

  before do
    create(:site_membership, site: site, user: investigator)
    create(:site_membership, site: site, user: admin)
  end

  describe "POST /api/v1/incidents/:incident_id/attachments" do
    it "attaches an uploaded file to the incident as the reporting worker" do
      post "/api/v1/incidents/#{incident.id}/attachments",
           params: { attachment: { file: upload } },
           headers: auth_headers(reporter)

      expect(response).to have_http_status(:created)
      expect(incident.reload.photos).to be_attached
      body = JSON.parse(response.body).fetch("data")
      expect(body.dig("attributes", "filename")).to eq("sample.png")
      expect(body.dig("attributes", "content_type")).to eq("image/png")
    end

    it "returns 422 when no file is given" do
      post "/api/v1/incidents/#{incident.id}/attachments",
           params: {},
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids users from another org" do
      other_org   = create(:organization)
      other_admin = create(:user, :admin, organization: other_org)
      post "/api/v1/incidents/#{incident.id}/attachments",
           params: { attachment: { file: upload } },
           headers: auth_headers(other_admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/incidents/:incident_id/attachments" do
    before do
      incident.photos.attach(io: File.open(fixture_path), filename: "sample.png", content_type: "image/png")
    end

    it "lists attachments with proxy URLs" do
      get "/api/v1/incidents/#{incident.id}/attachments", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body).fetch("data")
      expect(body.size).to eq(1)
      attrs = body.first["attributes"]
      expect(attrs["url"]).to be_present
      expect(attrs["signed_id"]).to be_present
      expect(attrs["filename"]).to eq("sample.png")
    end
  end

  describe "DELETE /api/v1/attachments/:id" do
    let(:attachment) do
      incident.photos.attach(io: File.open(fixture_path), filename: "sample.png", content_type: "image/png")
      incident.photos.attachments.last
    end

    it "purges the attachment when authorized" do
      attachment_id = attachment.id
      delete "/api/v1/attachments/#{attachment_id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(ActiveStorage::Attachment.where(id: attachment_id)).to be_empty
    end

    it "forbids unrelated users" do
      other_org   = create(:organization)
      other_admin = create(:user, :admin, organization: other_org)
      delete "/api/v1/attachments/#{attachment.id}", headers: auth_headers(other_admin)
      expect(response).to have_http_status(:not_found)
    end
  end
end
