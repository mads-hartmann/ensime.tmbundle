require "socket"

module Ensime
  
  # This is NOT The ENSIME server but a small server that can 
  # communicate with the ENSIME backend. We need this because 
  # TM commands can't keep an open TCP connection which ensime 
  # requires so instead this small server will keep a persistent
  # TCP connection to the ENSIME backend. 
  # The textmate commands will send a message to this server wich
  # will get forwarded to the ensime backend and the reply will get
  # send back to the textmate command.
  class Server
    
    def MESSAGE_HEADER_SIZE 
      6
    end 
    
    def TM_SERVER_PORT_FILE
      @project_dir + "/tm_port"
    end
    
    def ENSIME_PORT_FILE
      @project_dir + "/ensime_port"
    end
    
    def SUPPORT_FOLDER
      @support_dir
    end
  
    def initialize(projdir, supportdir)
      puts "initializing"
      @project_dir = projdir
      @support_dir = supportdir
      @socket = connect
      @helper = MessageHelper.new(MESSAGE_HEADER_SIZE())
      @message_count = 1
      # The following registerers the images you can display in the
      # completions
      
      imgpath = SUPPORT_FOLDER()+'/images'
      images = {
          "Function"   => "#{imgpath}/function.png",
          "Package" => "#{imgpath}/package.png",
          "Class" => "#{imgpath}/class.png",
          "Trait"   => "#{imgpath}/trait.png",
          "Object"    => "#{imgpath}/object.png",
      }
      `"$DIALOG" images --register  '#{images.to_plist}'`
      puts "Done initializing" 
    end
  
    # Start the server. 
    def start()
      puts "Server running"
      port = pick_port
      server = TCPServer.open(port)   
      loop {  # Servers run forever                        
        client = server.accept
        while((msg = @helper.read_message(client)) != "EOF")
        
          # create the right message structure and forward
          swank_message = @helper.create_message(msg, @message_count) 
          @socket.print(swank_message) 
        
          puts "Forwarded message:\n#{swank_message}\n"

          # Throw away messages till we find one with the correct
          # message number. 
          correct_message = false
          response = ""
          while(!correct_message) 
            response = @helper.read_message(@socket)
            countLength = @message_count.to_s.length
            msgNr = response.slice(response.length - (countLength + 1),countLength).to_i
            puts response
            if msgNr == @message_count
              correct_message = true
            else
            end  
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
      if File.exists?(TM_SERVER_PORT_FILE())
        File.delete(TM_SERVER_PORT_FILE())
      end
      file = File.new(TM_SERVER_PORT_FILE(), "w")
      file.print(port)
      file.close
      port
    end
  
    # Connects to the ENSIME backend
    # TODO: What if there's no port file?
    # TODO: What if the server isn't running?    
    def connect
      socket = 0
      begin
        file = File.new(ENSIME_PORT_FILE(), "r")
        port = file.gets.to_i
        file.close
        puts "connecting to: " + port.to_s
        socket = TCPSocket.open("127.0.0.1", port)
      rescue
        puts"Ensime not running. Retry in 2 seconds"
        sleep(2)
        socket = connect
      end
      return socket
    end    
  end

  class MessageHelper
    
    def initialize(msg_size)
      @message_size = msg_size
    end
    
    # This simply creates a message by prepending the length of the message
    # this is needed to the reciever knows how many bits to read.
    def prepend_length(msg)
      size = msg.length.to_s(16) # 16 bit 
      header = size.to_s.length.upto(@message_size-1).collect{0}
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
      length = socket.read(6).to_i(16)
      message = socket.read(length)
      return message
    end
  
  end
end