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

    it 'should resolve xref to inline anchor' do
      book, = to_epub 'inline-anchor-xref/book.adoc'
      chapter = book.item_by_href 'chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<a id="item1"></a>foo::bar'
      expect(chapter.content).to include '<a id="xref-item1" href="#item1" class="xref">[item1]</a>'
    end

    it 'should resolve xref to bibliography anchor' do
      book, = to_epub 'bibliography-xref/book.adoc'
      chapter = book.item_by_href 'chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<a id="item1"></a>[item1] foo::bar'
      expect(chapter.content).to include '<a id="xref-item1" href="#item1" class="xref">[item1]</a>'
    end
  end
end
