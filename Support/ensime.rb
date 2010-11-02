SUPPORT_LIB = ENV['TM_SUPPORT_PATH'] + '/lib/'
BUNDLE_LIB = ENV['TM_BUNDLE_SUPPORT'] + "/"

require "socket"
require 'pp' # pretty printing
require SUPPORT_LIB + 'io'
require SUPPORT_LIB + 'ui'
require SUPPORT_LIB + 'tm/htmloutput'
require SUPPORT_LIB + 'tm/process'
require BUNDLE_LIB + "sexpistol/sexpistol_parser.rb"
require BUNDLE_LIB + "sexpistol/sexpistol.rb"
# require SUPPORT_LIB + 'tm/require_cmd'
# require SUPPORT_LIB + 'escape'
# require SUPPORT_LIB + 'exit_codes'


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
      
      @helper = MessageHelper.new
      @procedure_id = 1
      @parser = Sexpistol.new
      @parser.ruby_keyword_literals = false      
    end
    
    def initialize_project
      if !@socket.nil?
        infoMsg = @helper.prepend_length("(swank:connection-info)")
        projectMsg = @helper.prepend_length("(swank:init-project #{read_project_file})")
        endMessage = @helper.prepend_length("EOF")

        @socket.print(infoMsg)
        @parser.parse_string(@helper.read_message(@socket))
        @socket.print(projectMsg)
        @parser.parse_string(@helper.read_message(@socket))
        @socket.print(endMessage)
        puts "ENSIME initialized. May the _ be with you."      
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
        			 ' (file "'+file+'" start 1 end '+caret_position.to_s+'))')
        endMessage = @helper.prepend_length("EOF")
        @socket.print(msg)
        puts @helper.read_message(@socket)
        @socket.print(endMessage)
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
        `osascript &>/dev/null \
          -e 'tell app "SystemUIServer" to activate'; \
         osascript &>/dev/null \
          -e 'tell app "TextMate" to activate' &`
        end
    end
    
    def completions(file, word)
      if !@socket.nil?
        msg = @helper.prepend_length('(swank:scope-completion "'+file+'" '+caret_position.to_s+' "'+word+'" nil)')
        endMessage = @helper.prepend_length("EOF")
        @socket.print(msg)
        swankmsg = @helper.read_message(@socket)
        @socket.print(endMessage)
        parsed = @parser.parse_string(swankmsg)
        compls = parsed[0][1][1].collect do |compl|
          {'display' => compl[1] }
        end
        #{:initial_filter => ""}
        TextMate::UI.complete(compls)
      end
    end
    
    private
    
    def print_type_errors(parsed)
      if parsed[0][1][1][3] == []
        TextMate::UI.tool_tip("<span style='color:green; font-weight:bold;'>No errors</span>", 
          {:format => :html, :transparent => false})
      else #there were errors
        errs = parsed[0][1][1][3].collect do |err|
          rel_path = err[13].gsub(ENV['TM_PROJECT_DIRECTORY'],"").gsub("/src/main/scala","") 
          "<span><span style='color:red; font-weight:bold;'>#{err[1]}: </span>" +
          "#{err[3]} " +
          "at line #{err[9]} " +
          "in #{rel_path}</span><br />"
        end
        TextMate::UI.tool_tip(errs.to_s, {:format => :html, :transparent => false})
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
      contents = File.open(ENV['TM_PROJECT_DIRECTORY'] + "/.ensime", "rb") { |f| f.read }
      return contents
    end
  end
  
  # This is NOT The ENSIME server but a small server that can 
  # communicate with the ENSIME backend. We need this because 
  # TM commands can't keep an open TCP connection which ensime 
  # requires so instead this small server will keep a persistent
  # TCP connection to the ENSIME backend. 
  # The textmate commands will send a message to this server wich
  # will get forwarded to the ensime backend and the reply will get
  # send back to the textmate command. 
  class Server
    
    def initialize
      @socket = connect
      @helper = MessageHelper.new
      @message_count = 1
    end
    
    # Start the server. 
    def start(io)
      port = pick_port
      server = TCPServer.open(port)   
      loop {  # Servers run forever                        
        client = server.accept
        while((msg = @helper.read_message(client)) != "EOF")
          
          # create the right message structure and forward
          swank_message = @helper.create_message(msg, @message_count) 
          @socket.print(swank_message) 
          
          io << "<p class='tm_message'>Forwarded message:\n#{swank_message}\n</p>"

          # Throw away messages till we find one with the correct
          # message number. 
          correct_message = false
          response = ""
          while(!correct_message) 
            response = @helper.read_message(@socket)
            countLength = @message_count.to_s.length
            msgNr = response.slice(response.length - (countLength + 1),countLength).to_i
            if msgNr == @message_count
              correct_message = true
            else
              io << "<p class='tm_message'>Throwing away:\n"+response+"</p>"
            end  
            io << "<p class='tm_message'>response:\n"+response+"</p>"
          end
            
          # Done, increment the count and return the response
          increment_message_count
          client.print(@helper.prepend_length(response)) 
        end
        client.close
      }

    end
            
    private 
    
    def increment_message_count 
      @message_count = @message_count + 1 
    end
            
    # Write the port this server is going to use to the file
    # TM_SERVER_PORT_FILE fíle.
    # TODO: Make it select a random open port
    def pick_port 
      port = 62174
      if File.exists?(TM_SERVER_PORT_FILE)
        File.delete(TM_SERVER_PORT_FILE)
      end
      file = File.new(TM_SERVER_PORT_FILE, "w")
      file.print(port)
      file.close
      port
    end
    
    # Connects to the ENSIME backend
    # TODO: What if there's no port file?
    # TODO: What if the server isn't running?    
    def connect
      file = File.new(ENSIME_PORT_FILE, "r")
      port = file.gets.to_i
      file.close
      return TCPSocket.open("127.0.0.1", port)      
    end    
  end
  
  class MessageHelper
    
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
    def create_message(call, count)
      msg = "(:swank-rpc #{call} #{count})"
      return prepend_length(msg)
    end

    # Reads a message from the socket. The first 6 bits are the 
    # length of the message. 
    def read_message(socket)
      length = socket.recv(6).to_i(16)
      message = socket.recv(length)
      return message
    end
    
  end
  
  class Helper
    def script_style_header
      return <<-HTML
  <!-- executor javascripts -->
  <script type="text/javascript" charset="utf-8">
  function press(evt) {
   if (evt.keyCode == 67 && evt.ctrlKey == true) {
     TextMate.system("kill -s USR1 #{::Process.pid};", null);
   }
  }

  function copyOutput(element) {
  output = element.innerText;
  cmd = TextMate.system('__CF_USER_TEXT_ENCODING=$UID:0x8000100:0x8000100 /usr/bin/pbcopy', function(){});
  cmd.write(output);
  cmd.close();
  element.innerText = 'output copied to clipboard';
  }

  </script>
  <!-- end javascript -->
  <style type="text/css">

  div.executor .controls {
    text-align:right;
    float:right;
  }
  div.executor .controls a {
    text-decoration: none;
  }

  div.executor pre em
  {
    font-style: normal;
    color: #FF5600;
  }

  div.executor p#exception strong
  {
    color: #E4450B;
  }

  div.executor p#traceback
  {
    font-size: 8pt;
  }

  div.executor blockquote {
    font-style: normal;
    border: none;
  }

  div.executor table {
    margin: 0;
    padding: 0;
  }

  div.executor td {
    margin: 0;
    padding: 2px 2px 2px 5px;
    font-size: 10pt;
  }

  div.executor div#_executor_output {
    white-space: normal;
    -khtml-nbsp-mode: space;
    -khtml-line-break: after-white-space;
  }

  div#_executor_output .out {  

  }
  div#_executor_output .err {  
    color: red;
  }
  div#_executor_output .echo {
    font-style: italic;
  }
  div#_executor_output .test {
    font-weight: bold;
  }
  div#_executor_output .test.ok {  
    color: green;
  }
  div#_executor_output .test.fail {  
    color: red;
  }
  div#exception_report pre.snippet {
    margin:4pt;
    padding:4pt;
  }
  </style>
  HTML
    end
  end
  
end