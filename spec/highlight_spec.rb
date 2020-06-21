# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Highlight' do
  it 'highlights code listings with coderay' do
    book, = to_epub fixture_file('source_highlight.adoc'), attributes: { 'source-highlighter' => 'coderay' }
    article = book.item_by_href 'source_highlight.xhtml'
    expect(article).not_to be_nil
    if Asciidoctor::Document.supports_syntax_highlighter?
      expect(article.content).to include '<span class="keyword">class</span> <span class="class">Foo</span>'
      expect(article.content).to include '<link rel="stylesheet" href="./coderay-asciidoctor.css"/>'
      expect(book.item_by_href('coderay-asciidoctor.css')).not_to be_nil
    else
      expect(article.content).to include '<span style="color:#080;font-weight:bold">class</span> <span style="color:#B06;font-weight:bold">Foo</span>'
    end
  end

  it 'highlights code listings with pygments.rb' do
    skip 'pygments.rb hangs on JRuby for Windows: https://github.com/asciidoctor/asciidoctor-epub3/issues/253' if RUBY_ENGINE == 'jruby' && Gem.win_platform?

    book, = to_epub fixture_file('source_highlight.adoc'), attributes: { 'source-highlighter' => 'pygments' }
    article = book.item_by_href 'source_highlight.xhtml'
    expect(article).not_to be_nil
    if Asciidoctor::Document.supports_syntax_highlighter?
      expect(article.content).to include '<span class="tok-k">class</span> <span class="tok-nc">Foo</span>'
      expect(article.content).to include '<link rel="stylesheet" href="./pygments-bw.css"/>'
      expect(book.item_by_href('pygments-bw.css')).not_to be_nil
    else
      expect(article.content).to include '<span style="font-weight: bold">class</span> <span style="font-weight: bold">Foo</span>'
    end
  end

  it 'highlights code listings with Rouge' do
    # TODO: This condition might be not quite correct
    skip 'No Rouge support in current Asciidoctor version' unless Asciidoctor::Document.supports_syntax_highlighter?

    book, = to_epub fixture_file('source_highlight.adoc'), attributes: { 'source-highlighter' => 'rouge' }
    article = book.item_by_href 'source_highlight.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<span class="k">class</span> <span class="nc">Foo</span>'
    expect(article.content).to include '<link rel="stylesheet" href="./rouge-bw.css"/>'
    expect(book.item_by_href('rouge-bw.css')).not_to be_nil
  end
end
