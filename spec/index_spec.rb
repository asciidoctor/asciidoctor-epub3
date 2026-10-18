# frozen_string_literal: true

require_relative 'spec_helper'

describe 'generated index' do
  it 'links nested and repeated terms across chapter files' do
    book = to_epub <<~'EOS'
      = Felines
      :doctype: book

      == Cats

      A https://example.org[((tiger))].
      (((Animals, Cats, Tiger)))

      == Dogs

      Another ((tiger)).

      [index]
      == Index

      Index introduction.
    EOS

    cats = book.item_by_href '_cats.xhtml'
    dogs = book.item_by_href '_dogs.xhtml'
    index = book.item_by_href '_index.xhtml'

    expect(cats.content).to include '<a href="https://example.org" class="link"><span id="__indexterm-1" class="indexterm"></span>tiger</a>'
    expect(dogs.content).to include '<span id="__indexterm-3" class="indexterm"></span>tiger'
    expect(index.content).to include '<div class="index-category">'
    expect(index.content).to include '<div class="index-entries" role="list">'
    expect(index.content).to include 'href="_cats.xhtml#__indexterm-1"'
    expect(index.content).to include 'href="_dogs.xhtml#__indexterm-3"'
    expect(index.content).to include 'Index introduction.'
  end

  it 'renders see, see-also, formatting, and XML-sensitive terms' do
    book = to_epub <<~'EOS'
      = Web
      :doctype: book

      == Formats

      ((Flash >> HTML 5)) ((HTML 5 &> CSS)) ((CSS)) ((*Tigers*)) ((Cats & kittens)).

      [index]
      == Index
    EOS

    index = book.item_by_href('_index.xhtml').content

    expect(index).to include 'Flash, see <a href="#__indextermdef-2">HTML 5</a>'
    expect(index).to include 'HTML 5, <a href="_formats.xhtml#__indexterm-2">Formats</a>; see also <a href="#__indextermdef-3">CSS</a>'
    expect(index).to include '<strong>Tigers</strong>'
    expect(index).to include 'Cats &amp; kittens'
  end

  it 'links a term in a chapter title to the chapter' do
    book = to_epub <<~'EOS'
      = Felines
      :doctype: book

      == ((Cats))

      [index]
      == Index
    EOS

    index = book.item_by_href('_index.xhtml').content
    expect(index).to include 'href="_cats.xhtml#_cats"'
  end

  it 'preserves authored content when there are no entries' do
    book = to_epub <<~'EOS'
      = Felines
      :doctype: book

      [index]
      == Index

      No entries.
    EOS

    index = book.item_by_href('_index.xhtml').content
    expect(index).to include 'No entries.'
    expect(index).not_to include 'index-category'
  end
end
