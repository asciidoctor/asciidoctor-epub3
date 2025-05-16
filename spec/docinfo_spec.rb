# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Docinfo' do
  it 'adds head docinfo' do
    book, = to_epub fixture_file('docinfo/head.adoc')
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<!-- Head docinfo -->'
  end

  it 'adds header docinfo' do
    book, = to_epub fixture_file('docinfo/header.adoc')
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<!-- Header docinfo -->'
  end

  it 'adds footer docinfo' do
    book, = to_epub fixture_file('docinfo/footer.adoc')
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<!-- Footer docinfo -->'
  end
end
