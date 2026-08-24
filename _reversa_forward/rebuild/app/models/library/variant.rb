# frozen_string_literal: true

module Library
  # Legacy origin: _wp_attachment_metadata['sizes'], a nested serialized array — one
  # entry per generated sub-size, each naming its own file, dimensions and type.
  #
  # BR-MIGRATE-088: every upload generates one file per registered sub-size. The row is
  # the promoted metadata (AD-03); the blob is the file. Both are derivable from the
  # asset's original and are regenerated together (AGG-Asset invariant).
  class Variant < ApplicationRecord
    self.table_name = "asset_variants"
    belongs_to :asset, class_name: "Library::Asset"
    has_one_attached :file, dependent: false

    validates :size_name, presence: true, uniqueness: { scope: :asset_id }
    validates :width, :height, numericality: { greater_than: 0 }

    # Destroying the row destroys the file, synchronously: a variant without its row is
    # an orphan the legacy also never left behind (wp_delete_attachment_files()).
    before_destroy { file.purge if file.attached? }

    # `_wp_attachment_metadata['sizes'][<name>]['file']` — the name wp_calculate_image_srcset()
    # builds the candidate URL from. Carried in the asset's metadata for corpus rows that
    # arrived without a blob (lib/seeding/pipeline.rb:485), read off the blob otherwise.
    def filename
      return file.filename.to_s if file.attached?

      asset.metadata.to_h.dig("sizes", size_name.to_s, "file")
    end
  end
end
