SUPPORT_LIB = ENV['TM_SUPPORT_PATH'] + '/lib/'
BUNDLE_LIB = ENV['TM_BUNDLE_SUPPORT'] + "/"

require 'strscan'
require 'stringio'
require "socket"
require 'pp' # pretty printing
require SUPPORT_LIB + 'io'
require SUPPORT_LIB + 'ui'
require SUPPORT_LIB + 'textmate'
require SUPPORT_LIB + 'tm/htmloutput'
require SUPPORT_LIB + 'tm/process'
require BUNDLE_LIB + "server.rb"
require BUNDLE_LIB + "scalaparser.rb"
require BUNDLE_LIB + "sexpistol/sexpistol_parser.rb"
require BUNDLE_LIB + "sexpistol/sexpistol.rb"

module Ensime
  
  MESSAGE_HEADER_SIZE = 6
  TM_SERVER_PORT_FILE = ENV['TM_PROJECT_DIRECTORY'] + "/tm_port"
  ENSIME_PORT_FILE = ENV['TM_PROJECT_DIRECTORY'] + "/ensime_port"
    
  # This is the client. Create an instance of this class to 
  # interact with the ensime backend. 
  # It does in fact communicate with the Ensime:Server which
  # in turn communicates with the ENSIME backend but this is 
  # transparrent to the user
  class Client
    
    def initialize
      begin
        @socket = connect
      rescue 
        @socket = nil
        puts "Please start the ensime backend first."
      end
      
      @helper = MessageHelper.new(MESSAGE_HEADER_SIZE)
      @procedure_id = 1
      @parser = Sexpistol.new
      @parser.ruby_keyword_literals = false
    end
    
    def initialize_project
      if !@socket.nil?
        project_config = read_project_file
        if !project_config.nil?
          infoMsg = @helper.prepend_length("(swank:connection-info)")
          projectMsg = @helper.prepend_length("(swank:init-project #{project_config})")
          endMessage = @helper.prepend_length("EOF")

          @socket.print(infoMsg)
          @parser.parse_string(@helper.read_message(@socket))
          @socket.print(projectMsg)
          @parser.parse_string(@helper.read_message(@socket))
          @socket.print(endMessage)
          puts "ENSIME is running. Please wait while it is analyzing your code"      
        else
          puts "Please create a .ensime project file and place it your\nprojects root directory"
        end
      end
    end
    
    def type_check_file(file) 
      if !@socket.nil?
        msg = @helper.prepend_length('(swank:typecheck-file "'+file+'")')
        endMessage = @helper.prepend_length("EOF")
        @socket.print(msg)
        swankmsg = @helper.read_message(@socket)
        @socket.print(endMessage)
        parsed = @parser.parse_string(swankmsg)
        print_type_errors(parsed)
      end
    end
    
    def type_check_all
      if !@socket.nil?
        msg = @helper.prepend_length("(swank:typecheck-all)")      
        endMessage = @helper.prepend_length("EOF")
        @socket.print(msg)
        swankmsg = @helper.read_message(@socket)
        @socket.print(endMessage)
        parsed = @parser.parse_string(swankmsg)
        print_type_errors(parsed)
      end
    end
    
    def organize_imports(file)
      if !@socket.nil?
        msg = @helper.prepend_length('(swank:perform-refactor '+@procedure_id.to_s+' organizeImports' +
        			 ' (file "'+file+'" start 1 end 1))')
        endMessage = @helper.prepend_length("EOF")
        @socket.print(msg)
        swankmsg = @helper.read_message(@socket)
        @socket.print(endMessage)
        parsed = @parser.parse_string(swankmsg)
        #parsed[0][1][1][7][0][3]
        print parsed[0][1][1][7][0][3]
        # puts parsed[0][1][1][5]
      end
    end
    
    def format_file(file)      
      if !@socket.nil?
        msg = @helper.prepend_length('(swank:format-source ("'+file+'"))')
        endMessage = @helper.prepend_length("EOF")
        @socket.print(msg)
        @helper.read_message(@socket) #throw it away
        @socket.print(endMessage)
        puts "Done reformatting source."
        # The following will force textmate to re-read the files from
        # the hdd. Otherwise the user wouldn't see the changes
        TextMate::rescan_project()
        end
    end
    
    def completions(file, word, line)
      if !@socket.nil?
        if line.include?('.')
          complete_type(file,word,line)
        else
          complete_scope(file,word,line)
        end
      end
    end
        
    private
    
    def complete_scope(file,word,line)
      msg = @helper.prepend_length('(swank:scope-completion "'+file+'" '+caret_position.to_s+' "'+word+'" nil)')        
      endMessage = @helper.prepend_length("EOF")
      @socket.print(msg)
      swankmsg = @helper.read_message(@socket)
      @socket.print(endMessage)
      parsed = @parser.parse_string(swankmsg)
      compls = parsed[0][1][1].collect do |compl|
        img = begin
          if compl[3].chars.to_a.last == '$' 
            "Object"
          else
            "Class"
          end
        end
        {'image' => img, 'display' => compl[1]}
      end
      TextMate::UI.complete(compls)
    end
    
    def complete_type(file,word,line)      
      partialCompletion = begin
        if word.chars.to_a.last == '.'
          ""
        else
          word
        end
      end 
      msg = @helper.prepend_length('(swank:type-completion "'+file+'" '+caret_position.to_s+' "'+partialCompletion+'" nil)')        
      endMessage = @helper.prepend_length("EOF")
      @socket.print(msg)
      swankmsg = @helper.read_message(@socket)
      @socket.print(endMessage)
      parsed = @parser.parse_string(swankmsg)
      # pp parsed
      compls = parsed[0][1][1].collect do |compl|
        funcs = ScalaParser::parse_function_signature(compl[3]) # arry of args, one arr for each func
        stopPoint = 0
        args = StringIO.new
        funcs.each do |funcArgs|
          stopPoint = stopPoint +1
          args << "("
          if !funcArgs.nil?
            funcArgs.each do |arg|
              args << ("${"+stopPoint.to_s+":"+arg.to_s+"}")
              stopPoint = stopPoint +1
            end
          end
          args << ")"
        end
        {'image' => "Function", 
         'display' => compl[1],
         'insert' => args.string}
      end
      TextMate::UI.complete(compls)
    end
    
    def print_type_errors(parsed)
      errors = parsed[0][1][1][3]
      if errors == []
        TextMate::UI.tool_tip("<span style='color:green; font-weight:bold; padding: 5px;'>W00t, no errors</span>", 
          {:format => :html, :transparent => false})
      else 
        msgs = errors.collect do |err|
          file_name = err[13].split("/").last
          "#{err[1]}: #{err[3]} at line #{err[9]} in #{file_name}"
        end
        item = TextMate::UI.menu(msgs)
        if !item.nil? #nil if user hits escape
          `mate #{errors[item][13]} -l #{errors[item][9]}`
        end
      end
    end
    
    # This method was a code snippet from Hans-Jörg Bibiko 
    # provided on the textmate dev ML 
    def caret_position
      lines = STDIN.readlines 

      # Find out the caret's position within the whole document as we may need to 
      # more back and forwards across line boundaries while building up the 
      # selector signature. 
      line_index = ENV['TM_LINE_INDEX'].to_i 
      line_number = ENV['TM_LINE_NUMBER'].to_i - 1 - 1  # starts from 1 and stop on line before 

      # caret_placement identifies the index of the character to the left of the caret's position. 
      caret_placement = (0..line_number).inject(0) {|sum, i| sum + lines[i].length} + line_index - 1 

      return caret_placement
    end
        
    # Connects to the Textmate ENSIME server backend
    # TODO: What if there's no port file?
    # TODO: What if the server isn't running?    
    def connect
      file = File.new(TM_SERVER_PORT_FILE, "r")
      port = file.gets.to_i
      file.close
      return TCPSocket.open("127.0.0.1", port)      
    end
    
    # TODO: What if there's not project file
    def read_project_file
      path = ENV['TM_PROJECT_DIRECTORY'] + "/.ensime"
      if File.exists?(path)
        contents = File.open(path, "rb") { |f| f.read }
        return contents
      else
        return nil
      end
    end
  end
  
end