# frozen_string_literal: true

require_relative 'spec_helper'

describe Asciidoctor::Epub3::Converter do
  describe '#convert' do
    it 'converts empty file to epub without exceptions' do
      to_epub fixture_file('empty.adoc')
    end

    it 'converts empty file to mobi without exceptions' do
      to_mobi fixture_file('empty.adoc')
    end

    it 'converts empty heredoc document to epub without exceptions' do
      to_epub <<~EOS
      EOS
    end

    it 'converts minimal heredoc document to epub without exceptions' do
      book = to_epub <<~EOS
      = Title
      EOS
      expect(book).to be_a(GEPUB::Book)
    end

    it 'converts chapter with unicode title to unicode filename' do
      _, out_file = to_epub fixture_file('unicode/book.adoc')
      Zip::File.open out_file do |zip|
        expect(zip.find_entry('EPUB/test-é.xhtml')).not_to be_nil
      end
    end

    it 'extracts book when given ebook-extract attribute' do
      _, out_file = to_epub fixture_file('minimal/book.adoc'), attributes: { 'ebook-extract' => '' }
      out_dir = out_file.dirname
      expect(out_dir.join('book', 'EPUB', 'package.opf')).to exist
    end

    it 'uses current date as fallback when date attributes cannot be parsed' do
      # TODO: assert that error log contains 'failed to parse revdate' error when we add test infrastructure for logs
      book, = to_epub fixture_file('minimal/book.adoc'), attributes: { 'revdate' => 'garbage' }
      expect(book.metadata.date.content).not_to be_nil
    end

    it 'adds listing captions by default' do
      book, = to_epub fixture_file('listing/book.adoc')
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<figcaption>Listing 1. .gitattributes</figcaption>'
    end

    it 'increments listing numbering across chapters' do
      book, = to_epub fixture_file('listing-chapter/book.adoc')
      chapter_b = book.item_by_href 'chapter-b.xhtml'
      expect(chapter_b).not_to be_nil
      expect(chapter_b.content).to include '<figcaption>Listing 2. .gitattributes</figcaption>'
    end

    it 'adds preamble chapter' do
      book, = to_epub fixture_file('preamble/book.adoc')
      spine = book.spine.itemref_list
      expect(spine).to have_size(2)

      preamble = book.items[spine[0].idref]
      expect(preamble).not_to be_nil
      expect(preamble.href).to eq('preamble.xhtml')
      expect(preamble.content).to include %(I am a preamble)
    end

    it 'converts appendix to a separate book chapter' do
      book, = to_epub fixture_file('appendix.adoc')
      spine = book.spine.itemref_list
      expect(spine).to have_size(2)

      appendix = book.items[spine[1].idref]
      expect(appendix).not_to be_nil
      expect(appendix.href).to eq('appendix.xhtml')
      expect(appendix.content).to include('Appendix A: Appendix')
    end

    it 'supports quotes in section titles' do
      book, = to_epub <<~EOS
= "Title"
      EOS
      chapter = book.item_by_href '_title.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include('<section class="chapter" title="&quot;Title&quot;')
    end

    it 'supports section numbers' do
      book, = to_epub <<~EOS
= Title
:sectnums:
:doctype: book

== Chapter
      EOS
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include('1. Chapter')
    end

    it 'converts multi-part book' do
      book, = to_epub fixture_file('multi-part.adoc')
      spine = book.spine.itemref_list
      expect(spine).to have_size(4)

      part2 = book.items[spine[2].idref]
      expect(part2.href).to eq('part-2.xhtml')
      expect(part2.content).to include %(Three)
      chapter21 = book.items[spine[3].idref]
      expect(chapter21.href).to eq('chapter-2-1.xhtml')
      expect(chapter21.content).to include %(Four)
    end

    it 'populates ebook subject from keywords' do
      book, = to_epub fixture_file('keywords/book.adoc')
      keywords = book.subject_list.map(&:content)
      expect(keywords).to eq(%w(a b c))
    end

    it 'adds front matter page with images' do
      book, = to_epub fixture_file('front-matter/book.adoc')
      spine = book.spine.itemref_list
      expect(spine).to have_size(2)

      front_matter = book.items[spine[0].idref]
      expect(front_matter).not_to be_nil
      expect(front_matter.href).to eq('front-matter.xhtml')
      expect(front_matter.content).to include 'Matter. Front Matter.'
      expect(book).to have_item_with_href 'square.png'
    end

    it 'adds multiple front matter page with images' do
      book, = to_epub fixture_file('front-matter-multi/book.adoc')
      spine = book.spine.itemref_list
      expect(spine).to have_size(3)

      front_matter1 = book.items[spine[0].idref]
      expect(front_matter1).not_to be_nil
      expect(front_matter1.href).to eq('front-matter.1.xhtml')
      expect(front_matter1.content).to include 'Matter. Front Matter.'
      expect(book).to have_item_with_href 'square.png'

      front_matter2 = book.items[spine[1].idref]
      expect(front_matter2).not_to be_nil
      expect(front_matter2.href).to eq('front-matter.2.xhtml')
      expect(front_matter2.content).to include 'Matter. Front Matter. 2'
      expect(book).to have_item_with_href 'square_blue.png'
    end

    it 'places footnotes in the same chapter' do
      book, = to_epub fixture_file('footnote/book.adoc')
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

    it 'supports custom epub-chapter-level' do
      book = to_epub <<~EOS
= Book
:epub-chapter-level: 2
:doctype: book

text0

== Level 1

text1

=== Level 2

text2

==== Level 3

text3
      EOS

      spine = book.spine.itemref_list
      expect(spine).to have_size(3)
    end

    it 'resolves deep includes relative to document that contains include directive' do
      book, = to_epub fixture_file('deep-include/book.adoc')
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<p>Hello</p>'
    end

    it 'adds no book authors if there are none' do
      book, = to_epub fixture_file('author/book-no-author.adoc')
      expect(book.creator).to be_nil
      expect(book.creator_list.size).to eq(0)
    end

    it 'adds a single book author' do
      book, = to_epub fixture_file('author/book-one-author.adoc')
      expect(book.creator).not_to be_nil
      expect(book.creator.content).to eq('Author One')
      expect(book.creator.role.content).to eq('aut')
      expect(book.creator_list.size).to eq(1)
    end

    it 'adds multiple book authors' do
      book, = to_epub fixture_file('author/book-multiple-authors.adoc')
      expect(book.metadata.creator).not_to be_nil
      expect(book.metadata.creator.content).to eq('Author One')
      expect(book.metadata.creator.role.content).to eq('aut')
      expect(book.creator_list.size).to eq(2)
      expect(book.metadata.creator_list[0].content).to eq('Author One')
      expect(book.metadata.creator_list[1].content).to eq('Author Two')
    end

    it 'adds the publisher if both publisher and producer are defined' do
      book, = to_epub fixture_file('author/book-one-author.adoc')
      expect(book.publisher).not_to be_nil
      expect(book.publisher.content).to eq('MyPublisher')
    end

    it 'adds the producer as publisher if no publisher is defined' do
      book, = to_epub fixture_file('author/book-no-author.adoc')
      expect(book.publisher).not_to be_nil
      expect(book.publisher.content).to eq('MyProducer')
    end

    it 'adds book series metadata' do
      book = to_epub <<~EOS
= Article
:series-name: My Series
:series-volume: 42
:series-id: bla
      EOS
      meta = book.metadata.meta_list[1]
      expect(meta).not_to be_nil
      expect(meta['property']).to eq('belongs-to-collection')
      expect(meta.content).to eq('My Series')
      expect(meta.refiner('group-position').content).to eq('42')
      expect(meta.refiner('dcterms:identifier').content).to eq('bla')
    end

    it 'adds toc to spine' do
      book = to_epub <<~EOS
= Title
:toc:

Text
      EOS
      spine = book.spine.itemref_list
      expect(spine).to have_size(2)
      toc = book.items[spine[0].idref]
      expect(toc).not_to be_nil
      expect(toc.href).to eq('toc.xhtml')
    end

    it "doesn't crash when sees inline toc" do
      to_epub <<~EOS
= Title

toc::[]
      EOS
    end

    it 'supports video' do
      book, = to_epub fixture_file('video/book.adoc')
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<video src="small.webm" width="400" controls="controls">'
      video = book.item_by_href 'small.webm'
      expect(video).not_to be_nil
      expect(video.media_type).to eq('video/webm')
    end

    it 'supports remote video' do
      book, = to_epub <<~EOS
= Article

video::http://nonexistent/small.webm[]
      EOS
      article = book.item_by_href '_article.xhtml'
      expect(article).not_to be_nil
      expect(article['properties']).to include('remote-resources')
      expect(article.content).to include '<video src="http://nonexistent/small.webm" controls="controls">'
      video = book.item_by_href 'http://nonexistent/small.webm'
      expect(video).not_to be_nil
      expect(video.media_type).to eq('video/webm')
    end

    it 'supports audio' do
      book, = to_epub fixture_file('audio/book.adoc')
      chapter = book.item_by_href '_chapter.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include '<audio src="small.mp3" controls="controls">'
      audio = book.item_by_href 'small.mp3'
      expect(audio).not_to be_nil
      expect(audio.media_type).to eq('audio/mpeg')
    end

    it 'supports remote audio' do
      book, = to_epub <<~EOS
= Article

audio::http://nonexistent/small.mp3[]
      EOS
      article = book.item_by_href '_article.xhtml'
      expect(article).not_to be_nil
      expect(article['properties']).to include('remote-resources')
      expect(article.content).to include '<audio src="http://nonexistent/small.mp3" controls="controls">'
      audio = book.item_by_href 'http://nonexistent/small.mp3'
      expect(audio).not_to be_nil
      expect(audio.media_type).to eq('audio/mpeg')
    end

    it 'supports horizontal dlist' do
      book = to_epub <<~EOS
= Article

[horizontal]
CPU:: The brain of the computer.
Hard drive:: Permanent storage for operating system and/or user files.
RAM:: Temporarily stores information the CPU uses during operation.
      EOS

      chapter = book.item_by_href '_article.xhtml'
      expect(chapter).not_to be_nil
      expect(chapter.content).to include <<~EOS
<tr>
<td class="hdlist1">
<p>
CPU
</p>
</td>
<td class="hdlist2">
<p>The brain of the computer.</p>
</td>
</tr>
      EOS
    end
  end
end
