# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Stem' do
  it 'converts stem block to <code>' do
    book, = to_epub fixture_file('stem/book.adoc')
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<code>\sqrt(4) = 2</code>'
  end

  it 'converts inline stem to <code>' do
    book, = to_epub fixture_file('inline-stem/book.adoc')
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<code class="literal">y=x^2 sqrt(4)</code>'
  end
end
