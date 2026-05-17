require "rails_helper"

RSpec.describe Witness, type: :model do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter) }

  describe "associations" do
    it "belongs to an incident" do
      witness = build(:witness, incident: incident)
      expect(witness.incident).to eq(incident)
    end

    it "exposes the incident's organization" do
      witness = create(:witness, incident: incident)
      expect(witness.organization).to eq(organization)
    end
  end

  describe "validations" do
    it "is valid with name only" do
      expect(build(:witness, incident: incident, email: nil, phone: nil, statement: nil)).to be_valid
    end

    it "requires a name" do
      witness = build(:witness, incident: incident, name: nil)
      expect(witness).not_to be_valid
      expect(witness.errors[:name]).to be_present
    end

    it "rejects names longer than 120 characters" do
      witness = build(:witness, incident: incident, name: "a" * 121)
      expect(witness).not_to be_valid
    end

    it "rejects malformed email" do
      witness = build(:witness, incident: incident, email: "not-an-email")
      expect(witness).not_to be_valid
      expect(witness.errors[:email]).to be_present
    end

    it "accepts a blank email" do
      witness = build(:witness, incident: incident, email: nil)
      expect(witness).to be_valid
    end
  end

  describe ".for_org" do
    it "scopes to incidents in the given org" do
      other_org      = create(:organization)
      other_site     = create(:site, organization: other_org)
      other_reporter = create(:user, organization: other_org)
      other_incident = create(:incident, organization: other_org, site: other_site, reporter: other_reporter)

      mine    = create(:witness, incident: incident)
      _theirs = create(:witness, incident: other_incident)

      expect(Witness.for_org(organization)).to contain_exactly(mine)
    end
  end

  describe "#soft_delete!" do
    it "sets deleted_at" do
      witness = create(:witness, incident: incident)
      expect { witness.soft_delete! }.to change(witness, :deleted_at).from(nil)
      expect(witness).to be_deleted
    end
  end
end
