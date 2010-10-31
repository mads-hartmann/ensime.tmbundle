SUPPORT_LIB = ENV['TM_SUPPORT_PATH'] + '/lib/'

require "socket"
require SUPPORT_LIB + 'io'
require SUPPORT_LIB + 'tm/htmloutput'
require SUPPORT_LIB + 'tm/process'
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
      @socket = connect
      @helper = MessageHelper.new
      @procedure_id = 1
    end
    
    def initialize_project
      infoMsg = @helper.prepend_length("(swank:connection-info)")
      projectMsg = @helper.prepend_length("(swank:init-project #{read_project_file})")
      endMessage = @helper.prepend_length("EOF")

      @socket.print(infoMsg)
      puts @helper.read_message(@socket)
      @socket.print(projectMsg)
      puts @helper.read_message(@socket)
      @socket.print(endMessage)
      # TODO: what to do with the answer?
    end
    
    def type_check_file(file) 
      msg = @helper.prepend_length('(swank:typecheck-file "'+file+'")')
      endMessage = @helper.prepend_length("EOF")
      @socket.print(msg)
      puts @helper.read_message(@socket)
      @socket.print(endMessage)
    end
    
    def type_check_all
      msg = @helper.prepend_length("(swank:typecheck-all)")      
      endMessage = @helper.prepend_length("EOF")
      @socket.print(msg)
      puts @helper.read_message(@socket)
      @socket.print(endMessage)
    end
    
    def organize_imports(file)
      msg = @helper.prepend_length('(swank:perform-refactor '+@procedure_id.to_s+' organizeImports' +
      			 ' (file "'+file+'" start 1 end 28))')
      endMessage = @helper.prepend_length("EOF")
      @socket.print(msg)
      puts @helper.read_message(@socket)
      @socket.print(endMessage)
    end
    
    def format_file(file)      
       msg = @helper.prepend_length('(swank:format-source ("'+file+'"))')
       endMessage = @helper.prepend_length("EOF")
       @socket.print(msg)
       puts @helper.read_message(@socket)
       @socket.print(endMessage)
    end
    
    private
        
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
    def start
      
      TextMate::HTMLOutput.show(
        :title => "Textmate ENSIME Server", 
        :sub_title => "Logs", 
        :html_head => Helper.new.script_style_header) do |io|
        
        
        io << "<pre></code>"

        port = pick_port
        server = TCPServer.open(port)   
        loop {  # Servers run forever                        
          client = server.accept
          while((msg = @helper.read_message(client)) != "EOF")
            io << "<p>Forwarding message:\n#{msg}\n</p>"
            
            # create the right message structure and forward
            @socket.print(@helper.create_message(msg, @message_count)) 
            

            # Throw away messages till we find one with the correct
            # message number. 
            correct_message = false
            response = ""
            while(!correct_message) 
              response = @helper.read_message(@socket)
              msgNr = response.slice(response.length-2,1).to_i
              if msgNr == @message_count
                correct_message = true
              else
                io << "Throwing away " + response
              end  
            
              io << "response:\n " + response
            end
              
            # Done, increment the count and return the response
            increment_message_count
            client.print(@helper.prepend_length(response)) 
          end
          client.close
        }
        
        io << "</code></pre>"
      end  
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