# frozen_string_literal: true

module Asciidoctor
  class AbstractNode
    # See https://asciidoctor.org/docs/user-manual/#book-parts-and-chapters
    # @return [Boolean]
    def chapter?
      return is_a?(Asciidoctor::Document) if document.doctype != 'book'

      return true if context == :preamble && level.zero?

      chapter_level = [document.attr('epub-chapter-level', 1).to_i, 1].max
      is_a?(Asciidoctor::Section) && level <= chapter_level
    end
  end
end
