# frozen_string_literal: true

require_relative 'spec_helper'

describe Asciidoctor::Epub3::Converter do
  describe '#convert' do
    it 'converts empty file to epub without exceptions' do
      infile = fixture_file 'empty.adoc'
      outfile = temp_file 'empty.epub'
      Asciidoctor.convert_file infile,
          to_file: outfile,
          backend: 'epub3',
          header_footer: true,
          mkdirs: true
      expect(File).to exist(outfile)
    end

    it 'converts empty file to mobi without exceptions' do
      skip_if_darwin

      infile = fixture_file 'empty.adoc'
      outfile = temp_file 'empty.mobi'
      Asciidoctor.convert_file infile,
          to_file: outfile,
          backend: 'epub3',
          header_footer: true,
          mkdirs: true,
          attributes: { 'ebook-format' => 'mobi' }
      expect(File).to exist(outfile)
    end
  end
end
