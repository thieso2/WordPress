# frozen_string_literal: true

# PT-002 -- Classifying content with terms. AGG-Term, BR-MIGRATE-052..064.
#
# Inspector contract (paradigm_decision.md): derived state is asserted as BEHAVIOUR.
# Nothing below asks whether a callback fired, what a validation is called, or how the
# `count` column is kept current -- only what an outside observer of the system sees.
#
# ⚠️ T-06 is in force throughout: `wp_terms` + `wp_term_taxonomy` collapse into ONE row
# per (term, taxonomy) pair, so the legacy's shared `term_id` -- one row serving both a
# category and a tag (BR-MIGRATE-052) -- does not exist here. Any oracle diff that turns
# on term-id sharing is an expected, recorded deviation, and no scenario below asserts it.

module ClassificationParityWorld
  # Scenarios name a taxonomy ("category") without always creating one first, so the
  # taxonomy is materialised on demand. Hierarchical, because every scenario that names
  # one either builds a hierarchy in it or is indifferent.
  def classification_taxonomy(name = "category")
    @classification_taxonomies ||= {}
    @classification_taxonomies[name] ||=
      Classification::Taxonomy.find_or_create_by!(name: name) do |taxonomy|
        taxonomy.hierarchical = true
        taxonomy.object_types = ["Publishing::Post"]
      end
  end

  def classification_remember(term)
    @classification_terms ||= {}
    @classification_terms[term.name] = term
    @classification_terms[term.slug] = term
    term
  end

  # Steps refer to a term by the name or the slug the feature used, whichever reads
  # better in the sentence, so both are accepted keys.
  def classification_term(key)
    (@classification_terms || {})[key] ||
      Classification::Term.find_by(name: key) ||
      Classification::Term.find_by!(slug: key)
  end

  def classification_record(status:, title:)
    Publishing::Article.create!(
      title: title, content: "", excerpt: "",
      status: status == "draft" ? "draft" : "published",
      published_at: status == "draft" ? nil : 1.day.ago
    )
  end
end
World(ClassificationParityWorld)

# ── Creating a term ───────────────────────────────────────────────────────────

Given("a hierarchical taxonomy {string}") do |name|
  # BR-MIGRATE-052's structural half: `taxonomy` is promoted from a varchar column on
  # term_taxonomy to a record of its own (target_data_model.md § Legacy origin).
  @taxonomy = Classification::Taxonomy.find_or_create_by!(name: name) do |taxonomy|
    taxonomy.hierarchical = true
    taxonomy.object_types = ["Publishing::Post"]
  end
  (@classification_taxonomies ||= {})[name] = @taxonomy
end

When("an editor creates the term {string} with slug {string}") do |name, slug|
  @term = classification_remember(
    Classification::Term.create!(taxonomy: @taxonomy, name: name, slug: slug)
  )
end

Then("the term exists in that taxonomy") do
  expect(Classification::Term.where(taxonomy_id: @taxonomy.id, slug: @term.slug)).to exist
  expect(@term.reload.taxonomy).to eq(@taxonomy)
end

Then("the term's content count is {int}") do |expected|
  # BR-MIGRATE-061. Read as a stored value on the term, exactly as any caller would --
  # the scenario is silent on how it got there, and so is this assertion.
  expect(@term.reload.count).to eq(expected)
end

# ── Uniqueness is an index, not a query loop (AD-05, F-DD-05) ─────────────────

Given("a term {string} with slug {string} and no parent in taxonomy {string}") do |name, slug, taxonomy_name|
  @taxonomy = classification_taxonomy(taxonomy_name)
  @term = classification_remember(
    Classification::Term.create!(taxonomy: @taxonomy, name: name, slug: slug, parent: nil)
  )
end

When("a second term with slug {string} and no parent in taxonomy {string} is written directly to the database") do |slug, taxonomy_name|
  # "written DIRECTLY to the database" is the whole point of the scenario. F-TAX-02:
  # wp_insert_term() inserts, re-queries for an older duplicate and then DELETES ITS OWN
  # ROWS, because term_taxonomy's only unique key is (term_id, taxonomy) and does not
  # cover this case (F-DD-05). AD-05 replaces that compensating dance with
  # `terms_unique ON (taxonomy_id, coalesce(parent_id, 0), slug)`. Going through the
  # model would prove a validation exists; going around it proves the guarantee holds.
  taxonomy = classification_taxonomy(taxonomy_name)
  @write_error = begin
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO terms (taxonomy_id, parent_id, name, slug)
      VALUES (#{taxonomy.id}, NULL, 'Duplicate', #{ActiveRecord::Base.connection.quote(slug)})
    SQL
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    e
  end
end

# "Then the write is rejected by a uniqueness constraint" is already defined in
# publishing_steps.rb against the same @write_error; it is deliberately not redefined
# here -- the two features assert the same property of two different unique indexes.

When("an editor creates a term with slug {string} whose parent is {string}") do |slug, parent_key|
  # coalesce(parent_id, 0) in the index is what makes this legal: the slug is unique
  # within (taxonomy, parent), not within the taxonomy.
  parent = classification_term(parent_key)
  @term = Classification::Term.new(taxonomy: parent.taxonomy, name: slug.titleize,
                                   slug: slug, parent: parent)
  @accepted = @term.save
  classification_remember(@term) if @accepted
end

Then("the term is created successfully") do
  expect(@accepted).to be(true), -> { @term.errors.full_messages.join("; ") }
  expect(@term.reload).to be_persisted
end

# ── BR-MIGRATE-063 (BR-TAX-13): the hierarchy is acyclic ──────────────────────

Given("a term {string} and its child {string}") do |parent_name, child_name|
  taxonomy = classification_taxonomy
  @parent_term = classification_remember(
    Classification::Term.create!(taxonomy: taxonomy, name: parent_name,
                                 slug: parent_name.parameterize)
  )
  @child_term = classification_remember(
    Classification::Term.create!(taxonomy: taxonomy, name: child_name,
                                 slug: child_name.parameterize, parent: @parent_term)
  )
end

When("an editor attempts to set {string} as a child of {string}") do |term_key, parent_key|
  term = classification_term(term_key)
  @accepted = term.update(parent: classification_term(parent_key))
end

Then("the change is rejected") do
  expect(@accepted).to be(false)
end

Then("the hierarchy is unchanged") do
  # The legacy's guard is a runtime `in_array( $parent, $ancestors )` break inside the
  # ancestor walk, which stops a corrupted chain from hanging the render but leaves the
  # corruption in the table. Here the row never changes at all.
  expect(@parent_term.reload.parent_id).to be_nil
  expect(@child_term.reload.parent_id).to eq(@parent_term.id)
end

# ── BR-MIGRATE-061 / 062: which records count ─────────────────────────────────

Given("a term {string}") do |name|
  @term = classification_remember(
    Classification::Term.create!(taxonomy: classification_taxonomy, name: name,
                                 slug: name.parameterize)
  )
end

Given("a {word} record classified under {string}") do |status, term_key|
  term = classification_term(term_key)
  @record = classification_record(status: status, title: "#{status.titleize} record")
  Classification::Assignment.create!(term: term, classifiable: @record)
  # A trashed record is a record that WAS published and no longer is -- which is the
  # case the count has to get right. Confirmed against the oracle: publishing, then
  # classifying, then trashing leaves the term at 0 for that record.
  @record.trash! if status == "trashed"
end

Given("a term {string} with exactly one published record classified under it") do |name|
  step "a term \"#{name}\""
  step "a published record classified under \"#{name}\""
  expect(@term.reload.count).to eq(1)
end

When("that record moves to status {string}") do |status|
  @record.update!(status: status)
end

# ── The surviving one-directional edge: Classification READS Publishing ───────

Given("a published record classified under two terms") do
  taxonomy = classification_taxonomy
  @two_terms = %w[Alpha Beta].map do |name|
    classification_remember(
      Classification::Term.create!(taxonomy: taxonomy, name: name, slug: name.parameterize)
    )
  end
  @record = classification_record(status: "published", title: "Doubly classified")
  @two_terms.each { |term| Classification::Assignment.create!(term: term, classifiable: @record) }
  @counts_before = @two_terms.map { |term| term.reload.count }
  expect(@counts_before).to eq([1, 1])
  # The id is captured HERE, not in the When: "When the record is deleted" is already
  # defined by discussion_steps.rb, so this file must not define it again, and it cannot
  # assume what that step leaves behind beyond the record being gone.
  @classified_record_id = @record.id
end

Then("no classification assignments reference that record") do
  # term_assignments.classifiable_* is the ONE relationship in the schema that cannot
  # carry a foreign key -- it is polymorphic across posts and assets, so
  # target_data_model.md records an orphan audit as the mitigation. This asserts the
  # orphan is never created in the first place on the delete path.
  expect(
    Classification::Assignment.where(classifiable_type: "Publishing::Post",
                                     classifiable_id: @classified_record_id)
  ).not_to exist
end

Then("both terms' counts are decremented") do
  after = @two_terms.map { |term| term.reload.count }
  expect(after).to eq(@counts_before.map { |before| before - 1 })
end
