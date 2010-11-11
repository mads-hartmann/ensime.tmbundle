require 'strscan'
require 'stringio'
require 'ostruct'

module ScalaParser
  
  class Expander
    
    def initialize(cPoint)
      @point = cPoint+1
    end
    
    # This will try to expand a type to something more meaningful
    # the current only use case for this is Functionx[a,b,...] and
    # it will expand to a lambda with proper tab-stops
    #
    # It returns an OpenStruct with 
    #   struct.string : the tab-stop-formatted string
    #   struct.point  : this is the next usable tab-stop
    def expand(strToExpand)
      
      struct = OpenStruct.new
      
      funcRegexp = /Function(\d)\[(.*)\]/
      scanner = StringScanner.new(strToExpand)
      grps = strToExpand.match(funcRegexp)
      if not grps.nil?
        size = grps.captures[0].to_i
        typstr = grps.captures[1].split(", ")
        str = StringIO.new
        str << "("
        (size).times do |cnt|
          tabstop = cnt+@point
          str << "${#{tabstop.to_s}:#{typstr[cnt]}}"
          if cnt+1 < size
            str << ", "
          end
        end
        str << ")"
        str << " => ${#{@point + size}:}"
        struct.string = str.string
        struct.point = @point + size + 1 
        return struct
      else
        struct.string = strToExpand
        struct.point = @point
        return struct
      end
    end
    
  end
  
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
  
  class TestExpander < Test::Unit::TestCase
    
    def test_expansion1
      expected = "(${1:A}) => ${2:}"
      result = ScalaParser::Expander.new(0).expand("Function1[A, B]")
      assert_equal(expected,result.string)
    end
    
    def test_expansion2
      expected = "(${3:A}) => ${4:}"
      result = ScalaParser::Expander.new(2).expand("Function1[A, B]")
      assert_equal(expected,result.string)
    end
    
  end
  
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