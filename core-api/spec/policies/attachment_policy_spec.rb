require "rails_helper"

RSpec.describe AttachmentPolicy do
  subject(:policy) { described_class.new(user, attachment) }

  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }

  let(:attachment) do
    incident.photos.attach(
      io: StringIO.new("fake-bytes"),
      filename: "f.png",
      content_type: "image/png"
    )
    incident.photos.attachments.last
  end

  before do
    create(:site_membership, site: site, user: investigator)
    create(:site_membership, site: site, user: admin)
  end

  describe "for an admin" do
    let(:user) { admin }
    it { expect(policy.show?).to be true }
    it { expect(policy.create?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for an investigator on the site" do
    let(:incident) { create(:incident, organization: organization, site: site, reporter: reporter, state: "investigating", assignee: investigator) }
    let(:user)     { investigator }
    it { expect(policy.create?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for the worker who reported a draft incident" do
    let(:user) { reporter }
    it { expect(policy.create?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for an unrelated worker" do
    let(:user) { create(:user, organization: organization) }
    it { expect(policy.create?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "for a user in another org" do
    let(:other_org) { create(:organization) }
    let(:user)      { create(:user, :admin, organization: other_org) }
    it { expect(policy.show?).to be false }
    it { expect(policy.create?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "Scope" do
    it "limits to attachments on visible incidents" do
      mine = attachment

      other_org      = create(:organization)
      other_site     = create(:site, organization: other_org)
      other_reporter = create(:user, organization: other_org)
      other_incident = create(:incident, organization: other_org, site: other_site, reporter: other_reporter)
      other_incident.photos.attach(io: StringIO.new("x"), filename: "x.png", content_type: "image/png")

      scope = described_class::Scope.new(admin, ActiveStorage::Attachment).resolve
      expect(scope).to include(mine)
      expect(scope.pluck(:record_id)).not_to include(other_incident.id)
    end
  end
end
