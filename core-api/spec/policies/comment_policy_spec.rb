require "rails_helper"

RSpec.describe CommentPolicy do
  subject(:policy) { described_class.new(user, comment) }

  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "submitted") }
  let(:comment)      { create(:comment, incident: incident, author: comment_author) }
  let(:comment_author) { investigator }

  before do
    create(:site_membership, site: site, user: investigator)
    create(:site_membership, site: site, user: admin)
  end

  describe "for an admin" do
    let(:user) { admin }
    it { expect(policy.show?).to be true }
    it { expect(policy.create?).to be true }
    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for an investigator who authored the comment" do
    let(:user) { investigator }
    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for an investigator who did not author the comment" do
    let(:user)           { create(:user, :investigator, organization: organization) }
    let(:comment_author) { admin }

    before { create(:site_membership, site: site, user: user) }

    it "may still update/destroy as on-site investigator" do
      expect(policy.update?).to be true
    end
  end

  describe "for a worker who authored their own comment" do
    let(:user)           { reporter }
    let(:incident)       { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }
    let(:comment_author) { reporter }

    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for a worker who did not author the comment" do
    let(:user)           { create(:user, organization: organization) }
    let(:comment_author) { investigator }

    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "for a user in another org" do
    let(:other_org) { create(:organization) }
    let(:user)      { create(:user, :admin, organization: other_org) }

    it { expect(policy.show?).to be false }
    it { expect(policy.update?).to be false }
  end

  describe "Scope" do
    it "only returns comments on incidents visible to the user" do
      mine = comment

      other_org      = create(:organization)
      other_site     = create(:site, organization: other_org)
      other_reporter = create(:user, organization: other_org)
      other_incident = create(:incident, organization: other_org, site: other_site, reporter: other_reporter)
      _theirs        = create(:comment, incident: other_incident, author: other_reporter)

      scope = described_class::Scope.new(admin, Comment).resolve
      expect(scope).to contain_exactly(mine)
    end
  end
end
