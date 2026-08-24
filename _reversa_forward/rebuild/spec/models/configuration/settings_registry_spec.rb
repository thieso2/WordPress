# frozen_string_literal: true

require "rails_helper"

# D-6: the typed settings registry. Unit-level proof of the casting and defaulting that
# the settings screens rely on — the SLICE of the ~130 options a human writes through a
# form. The registry is code (a product fact), so this spec needs no oracle.
RSpec.describe Configuration::SettingsRegistry do
  describe "the declared sections" do
    it "covers exactly the seven form-backed sections" do
      expect(described_class.sections).to contain_exactly(
        "general", "writing", "reading", "discussion", "media", "permalinks", "privacy"
      )
    end

    it "owns exactly the settings target_screens.md assigns to general" do
      names = described_class.section("general").map(&:name)
      expect(names).to eq(%w[blogname blogdescription siteurl home timezone_string
                             date_format time_format users_can_register default_role])
    end
  end

  describe "type casting (form strings -> stored shape)" do
    it "casts a checked checkbox to '1' and an absent one to '0'" do
      field = described_class.field("users_can_register")
      expect(field.cast("1")).to eq("1")
      expect(field.cast(nil)).to eq("0")
      expect(field.cast("")).to eq("0")
    end

    it "casts an integer field to a real Integer, defaulting a blank" do
      field = described_class.field("posts_per_page")
      expect(field.cast("25")).to eq(25)
      expect(field.cast("")).to eq(field.default)
    end

    it "passes a string field through unchanged" do
      expect(described_class.field("timezone_string").cast("Europe/Madrid")).to eq("Europe/Madrid")
    end
  end

  # BR-MIGRATE-014: esc_html on write for blogname/blogdescription, ENT_QUOTES, no
  # double-encoding.
  describe "the sanitize_option esc_html arm" do
    it "escapes & < > \" ' but does not double-encode an existing entity" do
      field = described_class.field("blogname")
      expect(field.cast(%(a & b < c > d " e ' f))).to eq("a &amp; b &lt; c &gt; d &quot; e &#039; f")
      expect(field.cast("already &amp; safe")).to eq("already &amp; safe")
      expect(field.cast("keep &#039; me")).to eq("keep &#039; me")
    end
  end

  describe ".current" do
    it "returns the declared default when the option is unset" do
      expect(described_class.current("posts_per_page")).to eq(10)
    end

    it "returns the stored value when set" do
      Configuration::Setting.set("posts_per_page", 42)
      expect(described_class.current("posts_per_page")).to eq(42)
    end
  end
end
