# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Highlight' do
  it 'highlights code listings with coderay' do
    book = to_epub <<~EOS
= Article
:source-highlighter: coderay

[source,ruby]
----
class Foo
  def bar?
    true
  end
end
----
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    if Asciidoctor::Epub3::Converter.supports_highlighter_docinfo?
      expect(article.content).to include '<span class="keyword">class</span> <span class="class">Foo</span>'
      expect(article.content).to include '.CodeRay .class{color:#458;font-weight:bold}'
    else
      expect(article.content).to include '<span style="color:#080;font-weight:bold">class</span> <span style="color:#B06;font-weight:bold">Foo</span>'
    end
  end

  it 'highlights code listings with pygments.rb' do
    skip 'pygments.rb hangs on JRuby for Windows: https://github.com/asciidoctor/asciidoctor-epub3/issues/253' if RUBY_ENGINE == 'jruby' && Gem.win_platform?

    book = to_epub <<~EOS
= Article
:source-highlighter: pygments

[source,ruby]
----
class Foo
  def bar?
    true
  end
end
----
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    if Asciidoctor::Epub3::Converter.supports_highlighter_docinfo?
      expect(article.content).to include '<span class="tok-k">class</span> <span class="tok-nc">Foo</span>'
      expect(article.content).to include 'pre.pygments .tok-nc { font-weight: bold }'
    else
      expect(article.content).to include '<span style="font-weight: bold">class</span> <span style="font-weight: bold">Foo</span>'
    end
  end

  it 'highlights code listings with Rouge' do
    # TODO: This condition might be not quite correct
    skip 'No Ruge support in current Asciidoctor version' unless Asciidoctor::Epub3::Converter.supports_highlighter_docinfo?

    book = to_epub <<~EOS
= Article
:source-highlighter: rouge

[source,ruby]
----
class Foo
  def bar?
    true
  end
end
----
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<span class="k">class</span> <span class="nc">Foo</span>'
    expect(article.content).to include 'pre.rouge .nc {
  font-weight: bold;
}'
  end
end
