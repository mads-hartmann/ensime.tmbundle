require 'strscan'
require 'stringio'

module ScalaParser
  class << self
    def parse_function_signature(typestring) 

      # The signature is always ... => Type. We don't care about
      # the end return type so we will trash the last => Type.

      funcs = typestring.split("=>").to_a
      funcs = funcs - [funcs.last]
      args = funcs.collect{ |func| func.strip }.to_s

      # Great, Now we're read to parse the rest of the string
      type = /\(.*\)?|\w+(\[.*\])?/
      tuple = /\(.*\)/
      comma = /\s*,?\s*/

      all = /#{type}|#{tuple}/

      s = StringScanner.new(args)

      arr = []
      attemps = 0
      while !s.eos?
        str = StringIO.new
        str << s.scan(all).to_s
        s.scan(comma)
        arr.push(str.string)
        attemps = attemps + 1
        if attemps == 50 
          raise typestring
        end
      end

      return arr
    end
  end
end

# interactive unit tests
if $0 == __FILE__
require "test/unit"
  
  class TestParser < Test::Unit::TestCase
    
    def test_parse_generic_type
      expected = ["Function[A,B]","String","Bool"]
      result = ScalaParser::parse_function_signature("Function[A,B],String, Bool => String")
      assert_equal(expected, result)
    end
    
    def test_parse_curried_type 
      expected = ["(B)","(Function2[B, A, B])"]
      result = ScalaParser::parse_function_signature("(B) => (Function2[B, A, B]) => B")
      assert_equal(expected,result)
    end
    
  end
end #testssca