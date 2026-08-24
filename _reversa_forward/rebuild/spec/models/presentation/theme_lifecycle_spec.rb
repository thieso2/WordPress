# frozen_string_literal: true

require "rails_helper"

# Presentation::Theme lifecycle (Wave 4, console.themes). DEV-011: a theme is data +
# template files, so activation is a row swap the render path follows, not a hook.
RSpec.describe Presentation::Theme do
  describe "#name" do
    it "reads theme.json's name" do
      t = described_class.new(slug: "x", version: "1", theme_json: { "name" => "Twenty Twenty-Five" })
      expect(t.name).to eq("Twenty Twenty-Five")
    end

    it "humanises the slug when theme.json carries no name" do
      t = described_class.new(slug: "my-theme", version: "1", theme_json: {})
      expect(t.name).to eq("My Theme")
    end
  end

  describe "#activate!" do
    it "makes exactly one theme active (BR-MIGRATE-001…006)" do
      a = described_class.create!(slug: "a", version: "1", active: true)
      b = described_class.create!(slug: "b", version: "1", active: false)
      b.activate!
      expect(described_class.where(active: true).pluck(:slug)).to eq(["b"])
      expect(a.reload.active?).to be(false)
    end
  end

  describe "#delete!" do
    it "removes an inactive theme and its templates" do
      t = described_class.create!(slug: "gone", version: "1", active: false)
      Composition::Template.create!(theme_slug: "gone", kind: "template", slug: "index",
                                    title: "Index", content: "<!-- wp:paragraph /-->")
      t.delete!
      expect(described_class.where(slug: "gone")).not_to exist
      expect(Composition::Template.where(theme_slug: "gone")).not_to exist
    end

    it "refuses to delete the active theme" do
      t = described_class.create!(slug: "live", version: "1", active: true)
      expect { t.delete! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(described_class.where(slug: "live")).to exist
    end
  end
end
