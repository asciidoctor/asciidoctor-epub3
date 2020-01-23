# frozen_string_literal: true

require_relative 'spec_helper'

describe Asciidoctor::Epub3::Converter do
  describe '#convert' do
    it 'converts empty file to epub without exceptions' do
      in_file = fixture_file 'empty.adoc'
      out_file = temp_file 'empty.epub'
      Asciidoctor.convert_file in_file,
          to_file: out_file,
          backend: 'epub3',
          header_footer: true,
          mkdirs: true
      expect(File).to exist(out_file)
    end

    it 'converts empty file to mobi without exceptions' do
      skip_if_darwin

      in_file = fixture_file 'empty.adoc'
      out_file = temp_file 'empty.mobi'
      Asciidoctor.convert_file in_file,
          to_file: out_file,
          backend: 'epub3',
          header_footer: true,
          mkdirs: true,
          attributes: { 'ebook-format' => 'mobi' }
      expect(File).to exist(out_file)
    end

    it 'converts chapter with unicode title to unicode filename' do
      infile = fixture_file 'unicode/spine.adoc'
      outfile = temp_file 'unicode.epub'
      Asciidoctor.convert_file infile,
          to_file: outfile,
          backend: 'epub3',
          header_footer: true,
          mkdirs: true
      prev_zip_encoding = Zip.force_entry_names_encoding
      begin
        Zip.force_entry_names_encoding = 'UTF-8'
        Zip::File.open outfile do |zip|
          expect(zip.find_entry('OEBPS/test-é.xhtml')).not_to be_nil
        end
      ensure
        Zip.force_entry_names_encoding = prev_zip_encoding
      end
    end

    it 'uses current date as fallback when date attributes cannot be parsed' do
      in_file = fixture_file 'minimal/book.adoc'
      out_file = temp_file 'garbage.epub'

      # TODO: assert that error log contains 'failed to parse revdate' error when we add test infrastructure for logs
      Asciidoctor.convert_file in_file,
          to_file: out_file,
          backend: 'epub3',
          header_footer: true,
          mkdirs: true,
          attributes: { 'revdate' => 'garbage' }

      book = GEPUB::Book.parse File.open(out_file)
      expect(book.metadata.date.content).not_to be_nil
    end
  end
end
