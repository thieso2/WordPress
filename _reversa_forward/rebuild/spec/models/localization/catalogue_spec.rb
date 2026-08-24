# frozen_string_literal: true

require "rails_helper"

# The catalogue seam. Loading and lookup are ABSORBED by the i18n gem; the REPRODUCED
# invariants are the lookup key (proven differentially against Translation_Entry::key in
# locale_differential_spec) and the MISS behaviour: translate()/_x() return the SOURCE
# string unchanged when the key is absent (translate(), l10n.php:194-196). The site ships
# only en_US, so every key misses and every call returns its source -- which is exactly
# why the 25 front-end screens render byte-identical English.
RSpec.describe Localization::Catalogue do
  describe ".translate" do
    it "returns the source string unchanged on a miss" do
      expect(described_class.translate("Save Changes")).to eq("Save Changes")
    end
  end

  describe ".translate_with_context (_x)" do
    # BR-I18N-09 / BR-MIGRATE-291: the context disambiguates the key, but the RETURN never
    # includes the context or the EOT separator (_x's contract, l10n.php:407). On a miss the
    # bare source string comes back -- NOT "noun\x04Post".
    it "returns the source string, never the context-prefixed key, on a miss" do
      got = described_class.translate_with_context("Post", "noun")
      expect(got).to eq("Post")
      expect(got).not_to include(Localization::Catalogue::EOT)
    end

    it "distinguishes two contexts by key while both miss to their shared source" do
      expect(described_class.context_key("Post", "noun")).not_to eq(described_class.context_key("Post", "verb"))
      expect(described_class.translate_with_context("Post", "noun")).to eq("Post")
      expect(described_class.translate_with_context("Post", "verb")).to eq("Post")
    end
  end

  describe ".installed_locales" do
    # get_available_languages() beyond the built-in en_US: none are installed today.
    it "is empty (only the built-in en_US ships)" do
      expect(described_class.installed_locales).to eq([])
    end
  end

  describe ".reload_all" do
    # The absorbed move: pointing the i18n gem at the switched locale. en_US maps to :en,
    # which is loaded, so the reload takes effect; the call is a no-op for a locale the gem
    # has no catalogue for (enforce_available_locales is not tripped).
    it "points I18n at an available locale and leaves an unavailable one untouched" do
      original = I18n.locale
      described_class.reload_all("en_US")
      expect(I18n.locale).to eq(:en)

      described_class.reload_all("fr_FR") # maps to I18n.default_locale, still :en here
      expect(I18n.locale).to eq(:en)
    ensure
      I18n.locale = original
    end
  end
end
