require "rails_helper"

RSpec.describe WitnessPolicy do
  subject(:policy) { described_class.new(user, witness) }

  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "submitted") }
  let(:witness)      { create(:witness, incident: incident) }

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

  describe "for an investigator on the site" do
    let(:user) { investigator }
    it { expect(policy.show?).to be true }
    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  describe "for the reporting worker" do
    let(:user) { reporter }
    let(:incident) { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }

    it { expect(policy.show?).to be true }
    it "may create on their own draft incident" do
      expect(policy.create?).to be true
    end
    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "for a user in another org" do
    let(:other_org) { create(:organization) }
    let(:user)      { create(:user, :admin, organization: other_org) }

    it { expect(policy.show?).to be false }
    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end

  describe "Scope" do
    it "only returns witnesses on incidents visible to the user" do
      mine = witness

      other_org      = create(:organization)
      other_site     = create(:site, organization: other_org)
      other_reporter = create(:user, organization: other_org)
      other_incident = create(:incident, organization: other_org, site: other_site, reporter: other_reporter)
      _theirs        = create(:witness, incident: other_incident)

      scope = described_class::Scope.new(admin, Witness).resolve
      expect(scope).to contain_exactly(mine)
    end
  end
end
