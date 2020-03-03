# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Xref' do
  context 'inter-chapter' do
    it 'resolves xref to top of chapter' do
      book, = to_epub fixture_file('inter-chapter-xref/book.adoc')
      chapter_a = book.item_by_href 'chapter-a.xhtml'
      expect(chapter_a).not_to be_nil
      expect(chapter_a.content).to include '<a id="xref--chapter-b" href="chapter-b.xhtml" class="xref">Chapter B</a>'
    end

    it 'resolves xref to section inside chapter' do
      book, = to_epub fixture_file('inter-chapter-xref-to-subsection/book.adoc')
      chapter_a = book.item_by_href 'chapter-a.xhtml'
      expect(chapter_a).not_to be_nil
      expect(chapter_a.content).to include '<a id="xref--chapter-b--getting-started" href="chapter-b.xhtml#getting-started" class="xref">Getting Started</a>'
    end
  end

  it 'resolves xref between subchapter include files' do
    book, = to_epub fixture_file('inter-subchapter-xref/book.adoc')
    chapter_a = book.item_by_href 'chapter-a.xhtml'
    expect(chapter_a).not_to be_nil
    expect(chapter_a.content).to include '<a id="xref--chapter-b--anchor" href="chapter-b.xhtml#anchor" class="xref">label</a>'
  end

  it 'resolves xref to inline anchor' do
    book, = to_epub fixture_file('inline-anchor-xref/book.adoc')
    chapter = book.item_by_href 'chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<a id="item1"></a>foo::bar'
    expect(chapter.content).to include '<a id="xref-item1" href="#item1" class="xref">[item1]</a>'
  end

  it 'resolves xref to bibliography anchor' do
    book, = to_epub fixture_file('bibliography-xref/book.adoc')
    chapter = book.item_by_href 'chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<a id="item1"></a>[item1] foo::bar'
    expect(chapter.content).to include '<a id="xref-item1" href="#item1" class="xref">[item1]</a>'
  end

  it 'resolves xref to bibliography chapter' do
    book, = to_epub fixture_file('bibliography-chapter/book.adoc')
    chapter = book.item_by_href 'chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<a id="xref--bibliography--pp" href="bibliography.xhtml#pp" class="xref">[pp]</a>'
  end

  it 'adds xref id to paragraph' do
    book = to_epub <<~EOS
= Article

[id=one]
One

[[two]]
Two

[#three]
Three

More text
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<p id="one">One</p>'
    expect(article.content).to include '<p id="two">Two</p>'
    expect(article.content).to include '<p id="three">Three</p>'
  end

  it 'displays anchor text' do
    book = to_epub <<~EOS
= Article

<<_subsection,link text>>

== Subsection
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<a id="xref-_subsection" href="#_subsection" class="xref">link text</a>'
  end
end
