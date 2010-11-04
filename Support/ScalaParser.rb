require 'strscan'
require 'stringio'

module ScalaParser
  class << self
    
    def parse_function_signature(typestring) 
      # The signature is always ... => Type. We don't care about
      # the end return type so we will trash the last => Type.
      rsltType = " => " + typestring.split(" => ").to_a.last
      args = typestring.gsub(rsltType,"").gsub(" => ","CURRIED")

      # Great, Now we're read to parse the rest of the string
      type = /\w+(\[.*\])?/
      tuple = /\(.*\)/
      comma = /\s*,?\s*/

      all = /#{type}|#{tuple}/
      
      arr = []
      
      arr = args.split("CURRIED").collect do |typ|
        if typ.to_s.length > 0
          argsArr = []
          attemps = 0
          typ = typ.strip
          removeParens = typ.slice(1,typ.length-2)
          if !removeParens.nil?           
            s = StringScanner.new(removeParens)
            while !s.eos? && attemps < 50
              str = StringIO.new
              str << s.scan(all).to_s
              s.scan(comma)
              argsArr.push(str.string)
              attemps = attemps + 1
            end
          end
          argsArr
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
    
    def test_parse_one_argument_type
      expected = [["String"]]
      result = ScalaParser::parse_function_signature("(String) => String")
      assert_equal(expected,result)
    end
    
    def test_parse_two_arguments_type
      expected = [["String","String"]]
      result = ScalaParser::parse_function_signature("(String, String) => String")
      assert_equal(expected,result)
    end
    
    def test_parse_curried_type_1
      expected = [["B"],["Function2[B, A, B]"]]
      result = ScalaParser::parse_function_signature("(B) => (Function2[B, A, B]) => B")
      assert_equal(expected,result)
    end

    def test_parse_curried_type_2
      expected = [["B"],["Function2[B, A]"]]
      result = ScalaParser::parse_function_signature("(B) => (Function2[B, A]) => B")
      assert_equal(expected,result)
    end
    
  end
end #testssca