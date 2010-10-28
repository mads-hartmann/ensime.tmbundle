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
    end
    
    def initialize_project
      msg = "(:swank-rpc (swank:connection-info) 1)"
      full = create_message(msg)
      @socket.print(full)
      tmp = @socket.recv(128)
      # TODO: what to do with the answer?
    end
    
    # creates a message that the ensime backend can read. This is done
    # by prepending the length of the message (hex-encoded).
    def create_message(msg)
      size = msg.length.to_s(16) # 16 bit 
      header = size.to_s.length.upto(MESSAGE_HEADER_SIZE-1).collect{0}
      header = header + size.split('')
      return header.to_s + msg
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
    end
    
    # Start the server. 
    def start
      
      TextMate::HTMLOutput.show(
        :title => "Textmate ENSIME Server", 
        :sub_title => "Logs", 
        :html_head => script_style_header) do |io|
        
        
        io << "<pre></code>"

        port = pick_port
        server = TCPServer.open(port)   
        loop {  # Servers run forever                        
          Thread.start(server.accept) do |client|
            msg = client.recv(128)
            io << "<p>Forwarding message:\n#{msg}\n</p>"
            @socket.print(msg)
            response = @socket.recv(128)
            client.print(response)    # Send the time to the client
            client.close              # Disconnect from the client
          end
        }
        
        io << "<code></pre>"
        
      end  
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