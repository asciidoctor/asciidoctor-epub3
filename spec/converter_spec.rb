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
      _, out_file = to_epub 'unicode/spine.adoc'
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

    it 'resolves deep includes relative to document that contains include directive' do
      book, = to_epub 'deep-include/book.adoc'
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<p>Hello</p>'
    end
  end
end
