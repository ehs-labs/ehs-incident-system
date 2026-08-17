require "rails_helper"

# ActiveStorage loads the configured variant transformer during boot, and the
# vips transformer requires a backend gem that this app does not bundle.
# Selecting anything but :disabled here aborts startup rather than failing at
# the first variant, so the choice is pinned.
RSpec.describe "ActiveStorage variant processing" do
  it "stays disabled so that booting needs no image backend gem" do
    expect(ActiveStorage.variant_processor).to eq(:disabled)
  end

  it "installs the null transformer instead of a vips or imagemagick backend" do
    expect(ActiveStorage.variant_transformer).to eq(ActiveStorage::Transformers::NullTransformer)
  end
end
