require "socket"

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
      full = encode_message(msg)
      @socket.print(full)
      tmp = @socket.recv(128)
      # TODO: what to do with the answer?
    end
    
    def encode_message(msg)
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
      port = pick_port
      server = TCPServer.open(port)   
      loop {  # Servers run forever                        
        Thread.start(server.accept) do |client|
          msg = client.recv(128)
          @socket.print(msg)
          response = @socket.recv(128)
          client.print(response)   # Send the time to the client
          client.close            # Disconnect from the client
        end
      }
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
  
  
end