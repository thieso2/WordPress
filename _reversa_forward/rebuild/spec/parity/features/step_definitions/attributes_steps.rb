# frozen_string_literal: true

# PT-008 -- Record attributes. BR-MIGRATE-021..028.
#
# AD-03 promoted every CORE-OWNED postmeta key to a real column, association or table.
# What is left is the residual bucket, and it has two shapes: `post_attributes` rows for
# single-valued keys (where the (post_id, key) unique index is the guarantee, AD-05) and
# `posts.residual_attributes` jsonb for the multi-valued ones, which cannot satisfy that
# index. Every step below reads the bucket the way an outside observer would -- by value,
# by public payload, or by counting rows after a delete -- and never by reaching for a
# callback, a validation name or a column default (the Inspector contract,
# paradigm_decision.md).

# ── AD-05 / F-META-02: the legacy's uniqueness was advisory ───────────────────
Given("a record carrying the attribute {string}") do |key|
  @record = Publishing::Article.create!(title: "Attribute host", content: "", excerpt: "")
  @attribute_key = key
  @attribute = Publishing::Attribute.create!(post: @record, key: key, value: "first value")
end

When("a second attribute row with the same record and key is written directly to the database") do
  # "written DIRECTLY to the database" is the whole point: BR-MIGRATE-021..028 under AD-05
  # say the guarantee is the unique index, not the model validation. add_metadata() ran
  # SELECT COUNT(*) then INSERT with NOTHING behind it (F-META-02), so duplicate rows
  # exist in the legacy despite $unique. Going through Publishing::Attribute here would
  # prove only that a validation exists.
  @write_error = begin
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO post_attributes (post_id, key, value)
      VALUES (#{@record.id}, #{ActiveRecord::Base.connection.quote(@attribute_key)}, '"second value"'::jsonb)
    SQL
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    e
  end
end

# ── AD-03's headline promotion: postmeta '_thumbnail_id' -> a foreign key ─────
Given("a record whose featured asset is a stored asset") do
  @asset = Library::Asset.create!(slug: "featured-asset", title: "Featured",
                                  mime_type: "image/jpeg", byte_size: 4096,
                                  width: 800, height: 600)
  @record = Publishing::Article.create!(title: "Has a featured asset", content: "", excerpt: "",
                                        featured_asset: @asset)
  expect(@record.reload.featured_asset).to eq(@asset)
end

When("that asset is deleted") do
  @deleted_asset_id = @asset.id
  @asset.destroy!
end

Then("the record's featured asset reference is cleared") do
  # The legacy stored this as postmeta '_thumbnail_id': a string in a key-value table,
  # with no referential integrity at all, so deleting the attachment left the meta row
  # pointing at nothing. Here it is a column with ON DELETE SET NULL.
  expect(@record.reload.featured_asset_id).to be_nil
  expect(@record.featured_asset).to be_nil
end

Then("no dangling reference remains") do
  dangling = ActiveRecord::Base.connection.select_value(<<~SQL)
    SELECT count(*) FROM posts p
      LEFT JOIN assets a ON a.id = p.featured_asset_id
     WHERE p.featured_asset_id IS NOT NULL AND a.id IS NULL
  SQL
  expect(dangling.to_i).to eq(0)
  expect(Library::Asset.where(id: @deleted_asset_id)).to be_empty
end

# ── Attributes are part of AGG-Post and do not outlive it ────────────────────
Given("a record carrying three arbitrary attributes") do
  @record = Publishing::Article.create!(title: "Three attributes", content: "", excerpt: "")
  %w[reading_time mood external_ref].each_with_index do |key, i|
    Publishing::Attribute.create!(post: @record, key: key, value: "value #{i}")
  end
  # The multi-valued half of the residual bucket goes with the record too -- it is a
  # column ON the record rather than a separate table (AD-03).
  @record.update!(residual_attributes: { "aliases" => %w[one two] })
  # Captured in the Given rather than in the When: "When the record is deleted" is a
  # shared phrasing owned by classification_steps.rb / library_steps.rb, so this file
  # must not assume which of them sets what.
  @attribute_host_id = @record.id
  expect(Publishing::Attribute.where(post_id: @record.id).count).to eq(3)
end

# NOTE: `When("the record is deleted")` is deliberately NOT defined here -- it is a
# shared phrasing already defined by another step file, and a second definition is a
# Cucumber::Glue::DuplicateStepDefinition / ambiguous match rather than a new assertion.

Then("no attribute rows reference that record") do
  expect(Publishing::Attribute.where(post_id: @attribute_host_id)).to be_empty
  orphans = ActiveRecord::Base.connection.select_value(<<~SQL)
    SELECT count(*) FROM post_attributes pa
      LEFT JOIN posts p ON p.id = pa.post_id
     WHERE p.id IS NULL
  SQL
  expect(orphans.to_i).to eq(0)
end

# ── TD-07 / F-DD-02: the legacy never indexes meta_value; reads by value ──────
Given("several records carrying an attribute with distinct values") do
  @attribute_key = "shelf"
  @records_by_value = {}
  %w[alpha beta gamma].each_with_index do |value, i|
    record = Publishing::Article.create!(title: "Shelved #{i}", content: "", excerpt: "")
    Publishing::Attribute.create!(post: record, key: @attribute_key, value: value)
    @records_by_value[value] = record
  end
  # A record carrying the same KEY with a different value, and one carrying a different
  # key with the SAME value: filtering has to discriminate on the pair, not on either half.
  decoy = Publishing::Article.create!(title: "Decoy", content: "", excerpt: "")
  Publishing::Attribute.create!(post: decoy, key: "other_key", value: "beta")
  @decoy = decoy
end

When("records are filtered by that attribute's value") do
  @sought_value = "beta"
  @matches = Publishing::Attribute.records_with(key: @attribute_key, value: @sought_value).to_a
end

Then("only the matching records are returned") do
  expect(@matches).to eq([@records_by_value.fetch(@sought_value)])
  expect(@matches).not_to include(@decoy)
  expect(@matches).not_to include(@records_by_value.fetch("alpha"))
  expect(@matches).not_to include(@records_by_value.fetch("gamma"))
end

# ── BR-MIGRATE-022 (legacy BR-META-04) ───────────────────────────────────────
Given("a record carrying a protected attribute") do
  @record = Publishing::Article.create!(title: "Has a secret", content: "", excerpt: "")
  @protected_key = "_internal_note"
  @public_key = "featured_note"
  Publishing::Attribute.create!(post: @record, key: @protected_key, value: "internal only")
  Publishing::Attribute.create!(post: @record, key: @public_key, value: "safe to show")
  # The multi-valued half is subject to the same rule.
  @record.update!(residual_attributes: { "_internal_log" => %w[a b], "aliases" => %w[one] })
  expect(Publishing::Attribute.protected_key?(@protected_key)).to be(true)
end

When("the record is fetched through the public API") do
  # ⚠️ The `PublicApi` context (target_architecture.md, 49 controllers) is not built in
  # Wave 0 -- config/routes.rb declares only the health check. What the scenario names is
  # nonetheless observable: the payload a public read of the record yields. It is taken
  # here from the model's public projection rather than over HTTP, and this step is the
  # single place to repoint at a controller once one exists.
  #
  # Oracle-confirmed shape (GET /wp/v2/posts/:id): an unexposed key is ABSENT from the
  # response object, not present with a null value.
  @response = {
    "id" => @record.id,
    "title" => @record.title,
    "attributes" => Publishing::Attribute.public_payload(@record)
  }
end

Then("the protected attribute is absent from the response") do
  attributes = @response.fetch("attributes")
  expect(attributes).not_to have_key(@protected_key)
  expect(attributes).not_to have_key("_internal_log")
  expect(@response.to_json).not_to include("internal only")
  # Absent, not blanked -- and the unprotected keys are still served, so the assertion
  # cannot pass by returning nothing at all.
  expect(attributes).to include(@public_key => "safe to show", "aliases" => %w[one])
end

# ── RISK-008 / implication 6: the slashing convention VANISHES ────────────────
# A regexp rather than {string}: the feature writes `Given an attribute value of
# "<value>"` with literal quotes, so the `"quoted"` example arrives as `""quoted""` and
# a cucumber-expression {string} cannot say which quotes are the delimiters.
Given(/^an attribute value of "(.*)"$/) do |value|
  @stored_value = value
  @record = Publishing::Article.create!(title: "Round trip", content: "", excerpt: "")
end

When("the value is stored and read back") do
  Publishing::Attribute.create!(post: @record, key: "round_trip", value: @stored_value)
  # Both storage shapes of the residual bucket, because implication 6 is a corpus-level
  # trap: a rule mis-read as assuming magic-quoted input would corrupt one of them.
  @record.update!(residual_attributes: { "round_trip_multi" => [@stored_value] })

  # A fresh read, not the in-memory object: the round trip has to include the database.
  Publishing::Attribute.uncached { @record.reload }
  @read_back = Publishing::Attribute.find_by!(post_id: @record.id, key: "round_trip").value
  @read_back_multi = Publishing::Post.find(@record.id).residual_attributes.fetch("round_trip_multi").first
end

Then("the value is byte-identical to what was stored") do
  expect(@read_back).to eq(@stored_value)
  expect(@read_back.bytes).to eq(@stored_value.bytes)
  expect(@read_back.encoding).to eq(Encoding::UTF_8)
  expect(@read_back_multi.bytes).to eq(@stored_value.bytes)
  # Named explicitly because it is the failure RISK-008 predicts: no escaping added, none
  # stripped. `\'` and `\\` would both be evidence of a surviving slashing convention.
  expect(@read_back.count("\\")).to eq(@stored_value.count("\\"))
  expect(@read_back.count("'")).to eq(@stored_value.count("'"))
  expect(@read_back.count('"')).to eq(@stored_value.count('"'))
end
