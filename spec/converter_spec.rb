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
  end
end
