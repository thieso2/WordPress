# frozen_string_literal: true

require "rails_helper"

# T-12: settings whose VALUES are record ids are remapped through the pipeline's id maps.
#
# ⚠️ The failure this guards against was SILENT: `sticky_posts: [15]` copied verbatim,
# the sticky article's new id was 14, and new id 15 belonged to a different post — so the
# front page floated the WRONG post. The mechanism worked, the data lied, nothing failed.
RSpec.describe "T-12 identifier-setting remap" do
  it "sticky_posts points at the post that is actually sticky in the oracle" do
    ids = Configuration::Setting["sticky_posts"]
    skip "corpus not seeded" if ids == false || ids.nil?

    titles = Publishing::Post.where(id: ids).pluck(:title)
    expect(titles).to eq(["Sticky front-page article"]),
                      "sticky_posts=#{ids.inspect} resolves to #{titles.inspect} — " \
                      "the T-12 remap in Seeding::Pipeline#remap_identifier_settings regressed"
  end

  it "wp_page_for_privacy_policy points at the privacy policy page" do
    id = Configuration::Setting["wp_page_for_privacy_policy"]
    skip "corpus not seeded" if id == false || id.nil? || id.to_i.zero?

    expect(Publishing::Post.find_by(id: id)&.slug).to eq("privacy-policy")
  end
end
