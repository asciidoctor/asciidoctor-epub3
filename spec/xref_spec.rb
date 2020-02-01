# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Xref' do
  context 'inter-chapter' do
    it 'should resolve xref to top of chapter' do
      book, = to_epub 'inter-chapter-xref/book.adoc'
      chapter_a = book.item_by_href 'chapter-a.xhtml'
      expect(chapter_a).not_to be_nil
      expect(chapter_a.content).to include '<a id="xref--chapter-b" href="chapter-b.xhtml" class="xref">Chapter B</a>'
    end

    it 'should resolve xref to section inside chapter' do
      book, = to_epub 'inter-chapter-xref-to-subsection/book.adoc'
      chapter_a = book.item_by_href 'chapter-a.xhtml'
      expect(chapter_a).not_to be_nil
      expect(chapter_a.content).to include '<a id="xref--chapter-b--getting-started" href="chapter-b.xhtml#getting-started" class="xref">Getting Started</a>'
    end
  end
end
