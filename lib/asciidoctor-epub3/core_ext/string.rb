require 'stringio' unless defined? StringIO

class String
  def to_ios
    StringIO.new self
  end unless String.respond_to? :to_ios
end
