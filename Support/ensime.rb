SUPPORT_LIB = ENV['TM_SUPPORT_PATH'] + '/lib/'
BUNDLE_LIB = ENV['TM_BUNDLE_SUPPORT'] + "/"

require 'strscan'
require 'stringio'
require "socket"
require 'pp' # pretty printing
require SUPPORT_LIB + 'io'
require SUPPORT_LIB + 'ui'
require SUPPORT_LIB + 'textmate'
require SUPPORT_LIB + 'tm/tempfile'
require SUPPORT_LIB + 'tm/htmloutput'
require SUPPORT_LIB + 'tm/process'
require SUPPORT_LIB + 'tm/save_current_document.rb'
require BUNDLE_LIB + "scalaparser.rb"
require BUNDLE_LIB + "sexpistol/sexpistol_parser.rb"
require BUNDLE_LIB + "sexpistol/sexpistol.rb"

module Ensime
  
  MESSAGE_HEADER_SIZE = 6
  ENSIME_MESSAGE_COUNTER_FILE = ENV['TM_PROJECT_DIRECTORY'] + "/.ensime.msg.counter"
  ENSIME_PORT_FILE = ENV['TM_PROJECT_DIRECTORY'] + "/ensime_port"
    
  # This is the client. Create an instance of this class to 
  # interact with the ensime backend. 
  # It does in fact communicate with the Ensime:Server which
  # in turn communicates with the ENSIME backend but this is 
  # transparrent to the user
  class Client
    
    def initialize(print_error_message = true)
      begin
        @socket = connect
      rescue 
        @socket = nil
        if print_error_message
          TextMate::UI.tool_tip("Please start the ensime backend first." )
        end
      end
      
      @procedure_id = 1
      @parser = Sexpistol.new
      @parser.ruby_keyword_literals = false
    end
    
    def initialize_project
      set_message_counter(0)
      if !@socket.nil?
        project_config = read_project_file
        if !project_config.nil?
          infoMsg = create_message("(swank:connection-info)")
          projectMsg = create_message("(swank:init-project #{project_config})")
          @socket.print(infoMsg)
          @parser.parse_string(get_response(@socket))
          @socket.print(projectMsg)
          @parser.parse_string(get_response(@socket))
          puts "ENSIME is running. Please wait while it is analyzing your code"      
        else
          puts "Please create a .ensime project file and place it your\nprojects root directory"
        end
      end
    end

    def type_check_all
      if !@socket.nil?
        TextMate.save_current_document()
        msg = create_message("(swank:typecheck-all)")
        @socket.print(msg)
        swankmsg = get_response(@socket)
        parsed = @parser.parse_string(swankmsg)
        print_type_errors(parsed)
      end
    end
    
    # The cleans up the import statements in the current file. 
    # 
    # It will save the current buffer to the HDD. Send a request to ENSIME to 
    # organize the imports on the file on disk. Then it reads the file on disk and replaces 
    # the content of the buffer with the contents of the file on disk
    def organize_imports(file)
      if !@socket.nil?
        TextMate.save_current_document()
        msg = create_message('(swank:perform-refactor '+@procedure_id.to_s+' organizeImports ' +
                             '(file "'+file+'"))')
        @socket.print(msg)
        swankmsg = get_response(@socket)
        
        # message to tell ensime to apply the changes
        parsed = @parser.parse_string(swankmsg)
        precedId = parsed[0][1][1][1]
        doItMessage = create_message("(swank:exec-refactor #{precedId} organizeImports)")
        
        @socket.print(doItMessage)
        rslt = get_response(@socket)
        rsltParsed = @parser.parse_string(rslt)
        TextMate::UI.tool_tip("Done organizing")
      end
      contents = File.open(file, "rb") { |f| f.read }
      puts contents
    end
    
    # This formats the current file nicely
    # 
    # It will save the current buffer to the HDD. Send a request to ENSIME to 
    # reformat the file on disk. Then it reads the file on disk and replaces 
    # the content of the buffer with the contents of the file on disk
    def format_file(file)      
      if !@socket.nil?
        TextMate.save_current_document()
        msg = create_message('(swank:format-source ("'+file+'"))')
        @socket.print(msg)
        get_response(@socket) #throw it away
        TextMate::UI.tool_tip("Done formatting")
      end
      contents = File.open(file, "rb") { |f| f.read }
      puts contents
    end
    
    def inspect
      if !@socket.nil?
        TextMate.save_current_document()
        point = caret_position
        msg = create_message('(swank:type-at-point "'+ENV['TM_FILEPATH']+'" '+point.to_s+')')
        @socket.print(msg)
        response = @parser.parse_string(get_response(@socket)) #throw it away
        puts response[0][1][1][1]
      end
    end
    
    # This does a rename refactoring 
    # 
    # It will save the current buffer to the HDD. Send a request to ENSIME to 
    # do a rename refactor on the the file on disk. Then it reads the file on 
    # disk and replaces the content of the buffer with the contents of the file on disk
    def rename(file)
      if !@socket.nil?
        selected = ENV['TM_SELECTED_TEXT']
        file = ENV['TM_FILEPATH']
        if !selected.nil?        
          TextMate.save_current_document()
          newName = TextMate::UI.request_string({
            :title => "Rename '#{selected}'",
            :prompt => "Enter the new name for '#{selected}'"})
          if !newName.nil?
            startCount = chars_up_to_line + ENV['TM_LINE_INDEX'].to_i + 1
            endCount = startCount + selected.length          
            msg = create_message('(swank:perform-refactor 1 rename ' + 
                                 '(file "'+file+'" '+
                                 'start '+startCount.to_s+' '+
                                 'end '+endCount.to_s+' '+
                                 'newName "'+newName+'"))')
            @socket.print(msg)
            swankmsg = get_response(@socket)
          
            # message to tell ensime to apply the changes
            parsed = @parser.parse_string(swankmsg)
            precedId = parsed[0][1][1][1]
            doItMessage = create_message("(swank:exec-refactor #{precedId} rename)")

            @socket.print(doItMessage)
            rslt = get_response(@socket)
            rsltParsed = @parser.parse_string(rslt)
            TextMate::UI.tool_tip("Done renaming")
          else
            TextMate::UI.tool_tip("Aborted refactoring")
          end
        else
          TextMate::UI.tool_tip("Please select something to rename.")
        end
      end
      contents = File.open(file, "rb") { |f| f.read }
      puts contents
    end
    
    def completions(file, word, line)
      if !@socket.nil?
        TextMate.save_current_document()
        if line.include?("import")
          complete_import(file,word,line)
        elsif line.include?('.')
          complete_type(file,word,line)
        else
          complete_scope(file,word,line)
        end
      end
    end
        
    private
    
    def complete_import(file,word,line)
       #msg = create_message('(swank:import-suggestions "'+file+'" '+caret_position.to_s+' ())')
       msg = create_message('(swank:package-member-completion "'+file+'" "n")')
       
       @socket.print(msg)
       swankmsg = get_response(@socket)
       parsed = @parser.parse_string(swankmsg)
       pp parsed
       # compls = parsed[0][1][1].collect do |compl|
       #          img = begin
       #            if compl[3].chars.to_a.last == '$' 
       #              "Object"
       #            else
       #              "Class"
       #            end
       #          end
       #          {'image' => img, 'display' => compl[1]}
       #        end
       #        TextMate::UI.complete(compls)
    end
    
    def complete_scope(file,word,line)
      msg = create_message('(swank:scope-completion "'+file+'" '+caret_position.to_s+' "'+word+'" nil)')
      @socket.print(msg)
      swankmsg = get_response(@socket)
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
      #puts caret_position.to_s
      msg = create_message('(swank:type-completion "'+file+'" '+caret_position.to_s+' "'+partialCompletion+'" nil)')        
      @socket.print(msg)
      swankmsg = get_response(@socket)
      parsed = @parser.parse_string(swankmsg)
      # pp parsed
      if parsed[0][1][1] == []
        puts "No completions."
      else
        compls = parsed[0][1][1].collect do |compl|
          funcs = ScalaParser::parse_function_signature(compl[3]) # arry of args, one arr for each func
          stopPoint = 0
          args = StringIO.new
          funcs.each do |funcArgs|
            stopPoint = stopPoint +1
            args << "("
            if !funcArgs.nil?
              funcArgs.each do |arg|
                expanded = ScalaParser::Expander.new(stopPoint).expand(arg.to_s)
                args << ("${"+stopPoint.to_s+":"+expanded.string+"}")
                stopPoint = expanded.point
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
    end
    
    def print_type_errors(parsed)
      errors = parsed[0][1][1][3]
      if errors == []
        TextMate::UI.tool_tip("<span style='color:green; font-weight:bold; padding: 5px;'>No errors</span>", 
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
    
    def set_message_counter(count)
      if File.exists?(ENSIME_MESSAGE_COUNTER_FILE)
        File.delete(ENSIME_MESSAGE_COUNTER_FILE)
      end
      file = File.new(ENSIME_MESSAGE_COUNTER_FILE, "w")
      file.print(count)
      file.close
    end
    
    def increment_message_counter 
      cnt = read_message_counter()
      newCnt = cnt+1
      set_message_counter(newCnt)
    end
    
    def read_message_counter
      if File.exists?(ENSIME_MESSAGE_COUNTER_FILE)
        contents = File.open(ENSIME_MESSAGE_COUNTER_FILE, "rb") { |f| f.read }
        return contents.to_i
      else
        return nil
      end
    end
    
    def get_response(socket)
      count = read_message_counter
      correct_message = false
      response = ""
      while(!correct_message) 
        response = read_message(socket)
        countLength = count.to_s.length
        msgNr = response.slice(response.length - (countLength + 1),countLength).to_i
        if msgNr == count
          correct_message = true
        else
        end
      end
      return response
    end
    
    # This simply creates a message by prepending the length of the message
    # this is needed to the reciever knows how many bits to read.
    def prepend_length(msg)
      size = msg.length.to_s(16) # 16 bit 
      header = size.to_s.length.upto(MESSAGE_HEADER_SIZE-1).collect{0}
      header = header + size.split('')
      return header.to_s + msg
    end
  
    # creates a message that the ensime backend can read. This is done
    # by prepending the length of the message (hex-encoded). and wrapping
    # the message in (:swank-rpc ..msg... count)
    def create_message(call)
      msg = "(:swank-rpc #{call} #{read_message_counter()})"
      return prepend_length(msg)
    end

    # Reads a message from the socket. The first 6 bits are the 
    # length of the message. 
    def read_message(socket)
      length = socket.read(6).to_i(16)
      message = socket.read(length)
      return message
    end
    
    # finds the number of chars in all of the lines before the 
    # current one.
    def chars_up_to_line
      lines = STDIN.readlines 
      if lines.length < ENV['TM_LINE_NUMBER'].to_i
        # The person has selected some text, so STDIN is 
        # just the word and not the document
        lines = File.open(ENV['TM_FILEPATH'],"r").readlines
      end

      line_number = ENV['TM_LINE_NUMBER'].to_i - 1 - 1  # starts from 1 and stop on line before
      count = (0..line_number).inject(0) {|sum, i| sum + lines[i].length}
      return count
    end
    
    # finds the number of chars up to the carets current posisiton.
    #
    # INFO: This method was a code snippet from Hans-Jörg Bibiko 
    # provided on the textmate dev ML 
    def caret_position      
      line_index = ENV['TM_LINE_INDEX'].to_i 

      # caret_placement identifies the index of the character 
      # to the left of the caret's position. 
      caret_placement = chars_up_to_line + line_index - 1 
      return caret_placement
    end
        
    # Connects to the Textmate ENSIME server backend
    # TODO: What if there's no port file?
    # TODO: What if the server isn't running?    
    def connect
      file = File.new(ENSIME_PORT_FILE, "r")
      port = file.gets.to_i
      file.close
      return TCPSocket.open("127.0.0.1", port)      
    end
    
    # TODO: What if there's not project file
    def read_project_file
      path = ENV['TM_PROJECT_DIRECTORY'] + "/.ensime"
      if File.exists?(path)
        config = StringIO.new
        file = File.open(path, "rb") 
        line = ""
        while (line = file.gets)
          if not line.strip.chars.first == ";"
            config << line
          end
        end
        return config.string
      else
        return nil
      end
    end
  end
  
end