# frozen_string_literal: true

require "rails_helper"

# The switch STACK: WP_Locale_Switcher (class-wp-locale-switcher.php), BR-I18N-06/07
# (BR-MIGRATE-288/289). switch_to_locale() pushes, restore_previous_locale() pops,
# restore_current_locale() unwinds to the request base. The stack lives in
# Localization::Current (per-request), never a process global (implication 1) -- proven
# here by resetting Current between examples and observing the stack empty.
RSpec.describe Localization::Switcher do
  before do
    Localization::Current.reset
    # Off the request path the base is the site locale; pin en_US so switches are the only
    # movement, and make de_DE/fr_FR available so switch_to_locale accepts them.
    allow(Localization::Locale).to receive(:site_locale).and_return("en_US")
    allow(Localization::Locale).to receive(:available?).and_return(true)
    # reload_all is the absorbed edge (I18n.locale); silence it so these unit tests do not
    # depend on which catalogues the i18n gem has loaded.
    allow(Localization::Catalogue).to receive(:reload_all)
  end

  # switch_to_locale(), :75-101.
  describe ".switch_to_locale" do
    it "pushes a frame, marks switched, and returns true" do
      expect(described_class.switch_to_locale("de_DE")).to be(true)
      expect(described_class.switched?).to be(true)
      expect(described_class.switched_locale).to eq("de_DE")
    end

    # :77 -- switching to the current locale is a no-op returning false.
    it "returns false and does nothing when the target equals the current locale" do
      expect(described_class.switch_to_locale("en_US")).to be(false)
      expect(described_class.switched?).to be(false)
    end

    # :81 -- an unavailable language is refused.
    it "returns false for an unavailable language" do
      allow(Localization::Locale).to receive(:available?).with("xx_XX").and_return(false)
      expect(described_class.switch_to_locale("xx_XX")).to be(false)
      expect(described_class.switched?).to be(false)
    end

    # BR-I18N-07 / BR-MIGRATE-289: switching reloads every loaded textdomain in the new
    # locale. The reload is the absorbed move (I18n.locale); assert it is triggered.
    it "reloads catalogues in the new locale" do
      expect(Localization::Catalogue).to receive(:reload_all).with("de_DE")
      described_class.switch_to_locale("de_DE")
    end
  end

  # switch_to_user_locale(), :111-114 -- the user's locale, keeping the user id as context.
  describe ".switch_to_user_locale" do
    it "switches to the user's locale and records the user id" do
      user = Struct.new(:id, :locale).new(42, "fr_FR")
      expect(described_class.switch_to_user_locale(user)).to be(true)
      expect(described_class.switched_locale).to eq("fr_FR")
      expect(described_class.switched_user_id).to eq(42)
    end
  end

  # restore_previous_locale(), :123-152.
  describe ".restore_previous_locale" do
    it "pops back through nested switches and returns the restored locale" do
      described_class.switch_to_locale("de_DE")
      described_class.switch_to_locale("fr_FR")

      expect(described_class.restore_previous_locale).to eq("de_DE") # back to the frame below
      expect(described_class.switched_locale).to eq("de_DE")
      expect(described_class.restore_previous_locale).to eq("en_US") # stack empty -> base
      expect(described_class.switched?).to be(false)
    end

    # :126 -- popping an empty stack returns false.
    it "returns false when nothing is switched" do
      expect(described_class.restore_previous_locale).to be(false)
    end
  end

  # restore_current_locale(), :161-169 -- collapse straight back to the request base.
  describe ".restore_current_locale" do
    it "unwinds every nested switch back to the base in one call" do
      described_class.switch_to_locale("de_DE")
      described_class.switch_to_locale("fr_FR")

      expect(described_class.restore_current_locale).to eq("en_US")
      expect(described_class.switched?).to be(false)
    end

    it "returns false when nothing is switched" do
      expect(described_class.restore_current_locale).to be(false)
    end
  end

  # implication 1: the stack is per-request. A reset (what Rails does between requests)
  # empties it, so a switch cannot bleed across the boundary.
  it "does not survive a Current reset" do
    described_class.switch_to_locale("de_DE")
    expect(described_class.switched?).to be(true)

    Localization::Current.reset
    expect(described_class.switched?).to be(false)
  end
end
