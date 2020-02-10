# frozen_string_literal: true

require_relative 'spec_helper'

describe Asciidoctor::Epub3::Converter do
  describe '#convert' do
    it 'converts empty file to epub without exceptions' do
      to_epub 'empty.adoc'
    end

    it 'converts empty file to mobi without exceptions' do
      to_mobi 'empty.adoc'
    end

    it 'converts chapter with unicode title to unicode filename' do
      _, out_file = to_epub 'unicode/book.adoc'
      Zip::File.open out_file do |zip|
        expect(zip.find_entry('OEBPS/test-é.xhtml')).not_to be_nil
      end
    end

    it 'uses current date as fallback when date attributes cannot be parsed' do
      # TODO: assert that error log contains 'failed to parse revdate' error when we add test infrastructure for logs
      book, = to_epub 'minimal/book.adoc', attributes: { 'revdate' => 'garbage' }
      expect(book.metadata.date.content).not_to be_nil
    end

    it 'adds listing captions by default' do
      book, = to_epub 'listing/book.adoc'
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<figcaption>Listing 1. .gitattributes</figcaption>'
    end

    it 'increments listing numbering across chapters' do
      book, = to_epub 'listing-chapter/book.adoc'
      chapter_b = book.item_by_href 'chapter-b.xhtml'
      expect(chapter_b).not_to be_nil
      expect(chapter_b.content).to include '<figcaption>Listing 2. .gitattributes</figcaption>'
    end

    it 'populates ebook subject from keywords' do
      book, = to_epub 'keywords/book.adoc'
      keywords = book.subject_list.map(&:content)
      expect(keywords).to eq(%w(a b c))
    end

    it 'adds front matter page with images' do
      book, = to_epub 'front-matter/book.adoc'
      front_matter = book.item_by_href 'front-matter.xhtml'
      expect(front_matter).not_to be_nil
      expect(front_matter.content).to include 'Matter. Front Matter.'
      expect(book).to have_item_with_href 'square.png'
    end

    it 'places footnotes in the same chapter' do
      book, = to_epub 'footnote/book.adoc'
      chapter_a = book.item_by_href 'chapter-a.xhtml'
      chapter_b = book.item_by_href 'chapter-b.xhtml'
      expect(chapter_a).not_to be_nil
      expect(chapter_b).not_to be_nil

      expect(chapter_a.content).to include 'A statement.<sup class="noteref">[<a id="noteref-1" href="#note-1" epub:type="noteref">1</a>]</sup>'
      footnote = '<aside id="note-1" epub:type="footnote">
<p><sup class="noteref"><a href="#noteref-1">1</a></sup> Clarification about this statement.</p>
</aside>'
      expect(chapter_a.content).to include footnote
      expect(chapter_b.content).not_to include footnote
    end

    it 'resolves deep includes relative to document that contains include directive' do
      book, = to_epub 'deep-include/book.adoc'
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<p>Hello</p>'
    end
  end
end
