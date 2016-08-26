require 'stringio' unless defined? StringIO

class String
  def to_ios
    StringIO.new self
  end unless method_defined? :to_ios
end
