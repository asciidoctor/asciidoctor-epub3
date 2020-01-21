# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils' unless defined? FileUtils

describe 'Asciidoctor::Epub3::Converter - Xref' do
  context 'inter-chapter' do
    it 'should resolve xref to top of chapter' do |_example|
      FileUtils.mkdir_p temp_dir
      book_file = File.join temp_dir, 'book.adoc'
      chapter_a_file = File.join temp_dir, 'chapter-a.adoc'
      chapter_b_file = File.join temp_dir, 'chapter-b.adoc'

      File.write chapter_a_file, <<~'EOS', encoding: 'UTF-8'
      = Chapter A

      This is chapter A.
      There's not much too it.

      Time to move on to <<chapter-b#>>.
      EOS

      File.write chapter_b_file, <<~'EOS', encoding: 'UTF-8'
      = Chapter B

      Not much to show here either.
      EOS

      File.write book_file, <<~'EOS', encoding: 'UTF-8'
      = Book Title
      :doctype: book
      :idprefix:
      :idseparator: -

      include::chapter-a.adoc[]

      include::chapter-b.adoc[]
      EOS

      doc = Asciidoctor.convert_file book_file, backend: 'epub3', header_footer: true
      spine_items = doc.references[:spine_items]
      (expect spine_items).to have_size 2
      chapter_a_content = doc.references[:spine_items][0].content
      (expect chapter_a_content).to include '<a href="chapter-b.xhtml" class="xref">Chapter B</a>'
    end

    it 'should resolve xref to section inside chapter' do |_example|
      FileUtils.mkdir_p temp_dir
      book_file = File.join temp_dir, 'book.adoc'
      chapter_a_file = File.join temp_dir, 'chapter-a.adoc'
      chapter_b_file = File.join temp_dir, 'chapter-b.adoc'

      File.write chapter_a_file, <<~'EOS', encoding: 'UTF-8'
      = Chapter A

      This is chapter A.
      There's not much too it.

      Time to move on to <<chapter-b#getting-started>>.
      EOS

      File.write chapter_b_file, <<~'EOS', encoding: 'UTF-8'
      = Chapter B

      == Getting Started

      Now we can really get to it!
      EOS

      File.write book_file, <<~'EOS', encoding: 'UTF-8'
      = Book Title
      :doctype: book
      :idprefix:
      :idseparator: -

      include::chapter-a.adoc[]

      include::chapter-b.adoc[]
      EOS

      doc = Asciidoctor.convert_file book_file, backend: 'epub3', header_footer: true
      spine_items = doc.references[:spine_items]
      (expect spine_items).to have_size 2
      chapter_a_content = doc.references[:spine_items][0].content
      (expect chapter_a_content).to include '<a href="chapter-b.xhtml#getting-started" class="xref">Getting Started</a>'
    end
  end
end
