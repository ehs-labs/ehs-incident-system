require "rails_helper"

RSpec.describe CorrectiveActionEvent, type: :model do
  describe "validations" do
    it "accepts each documented event name" do
      CorrectiveActionEvent::EVENT_NAMES.each do |name|
        evt = build(:corrective_action_event, event_name: name)
        expect(evt).to be_valid, "expected #{name.inspect} to be a valid event name"
      end
    end

    it "rejects an unknown event name" do
      evt = build(:corrective_action_event, event_name: "exploded")
      expect(evt).not_to be_valid
      expect(evt.errors[:event_name]).to be_present
    end

    it "rejects a note longer than 2000 characters" do
      evt = build(:corrective_action_event, note: "x" * 2001)
      expect(evt).not_to be_valid
    end

    it "accepts a nil note" do
      evt = build(:corrective_action_event, note: nil)
      expect(evt).to be_valid
    end
  end

  describe "cascade on parent delete" do
    it "is destroyed when its corrective_action is destroyed" do
      action = create(:corrective_action)
      evt    = create(:corrective_action_event, corrective_action: action)

      action.destroy!
      expect(CorrectiveActionEvent.where(id: evt.id)).to be_empty
    end
  end
end
