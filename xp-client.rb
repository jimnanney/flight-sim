# frozen_string_literal: true

require 'socket'
require 'ipaddr'
require 'pry'

module XplaneController
  class RefMessage
    attr_reader :index, :value

    def initialize(packet)
      @index, @value = packet.unpack('lf')
    end
  end

  class Message
    def self.from_packet(packet)
      packet_type = packet.unpack1('Z*')
      case packet_type
      when 'RREF,'
        index, value = packet[5..].unpack('lf')
      end
    end
  end

  class Beacon
    attr_reader :major, :minor, :app_host, :version, :role, :port, :computer_name, :raknet_port, :resolved, :ip_address

    def initialize(packet_bytes, sender)
      @resolved, @ip_address = sender[-2..]
      @packet_type, @major, @minor, @app_host, @version, @role, @port, @computer_name, @raknet_port =  packet_bytes.unpack('Z*CCllLSZ*S')
    end

    def main?
      @role == 1
    end

    def display_values
      puts "major: #{major}, minor: #{minor}, app_host: #{app_host}, version: #{version}, role: #{role}, port: #{port}, computer_name: #{computer_name}, raknet_port: #{raknet_port}"
    end
  end

  class Client
    attr_reader :address, :port

    MCAST_ADDRESS = '239.255.1.1'
    BIND_ADDRESS = '0.0.0.0'
    MCAST_PORT = '49707'

    def initialize(address=nil, port=nil)
      @address = address
      @port = port
      @datarefs = {}
      @active = []
      @index = 0

      find_main if address.nil?
      puts "Discovered X-Plane Server on: #{@address}:#{@port}"
      @c = UDPSocket.new
      @c.bind "127.0.0.1", 0
      puts "Listening on #{@c.addr.last}:#{@c.addr[1]}"
    end

    def find_main
      socket = UDPSocket.new
      membership = IPAddr.new(MCAST_ADDRESS).hton + IPAddr.new(BIND_ADDRESS).hton
      socket.setsockopt(:IPPROTO_IP, :IP_ADD_MEMBERSHIP, membership)
      socket.setsockopt(:SOL_SOCKET, :SO_REUSEPORT, 1) # if mac, if not mac use SO_REUSEADDR

      socket.bind(BIND_ADDRESS, MCAST_PORT)
      responder = nil
      server = loop do
        packet_bytes = socket.recvfrom(1500)
        responder = Beacon.new(packet_bytes[0], packet_bytes[1])

        break if responder.main?
      end
      @address = responder.ip_address
      @port = responder.port
    end

    def local_ip
      orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true  # turn off reverse DNS resolution temporarily
      UDPSocket.open do |s|
        s.connect '8.8.8.8', 1
        s.addr.last
      end
    ensure
      Socket.do_not_reverse_lookup = orig
    end

    def subscribe(freq: 20, dataref_name:, &block)
      @datarefs[dataref_name] = @index
      @datarefs[@index] = {dataref: dataref_name, index: @index, callback: block}
      message = ["RREF", freq, @index, dataref_name, ""].pack("Z*llZ*A#{400 - dataref_name.length - 1}")
      send(message)
      @index = @index + 1
    end

    def send(message)
      @c.send(message, 0, @address, @port)
    end

    def unsubscribe(index: nil, dataref_name: nil)
      return unless index || dataref_name

      index ||= @datarefs.delete(dataref_name)
      ref = @datarefs.delete(index)
      message = ["RREF", 0, ref[:dataref]].pack('Z*lZ*')

      send(message)
    end

    def set_dataref(dataref, value)
      message = ["DREF", value, dataref, ""].pack("Z*fZ*A#{500 - dataref.length - 1}")
      send(message)
    end

    def listen
      loop do
        #x = recv
        x = @c.recv(1500)
        i,v = Message.from_packet(x)
        dr = @datarefs[i]
        if dr[:callback]
          dr[:callback].call(v)
        end
      end
    ensure
      @c.close
    end

    def shutdown
      @c.close
    end

    def recv
      # emulate blocking recvfrom
      x = @c.recvfrom_nonblock(1500)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
      i,v = Message.from_packet(x[0])
      dr = @datarefs[i]
      if dr[:callback]
        dr[:callback].call(v)
      end
    rescue IO::WaitReadable
      IO.select([@c])
      retry
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  dr = "sim/cockpit2/radios/actuators/com2_standby_frequency_hz"
  client = XplaneController::Client.new
  com2_freq_khz = nil
  client.subscribe(dataref_name: dr) do |v|
    if com2_freq_khz != v
      puts "COM2 Standby Frequency khz: #{v}"
      com2_freq_khz = v
    end
  end
  loop do
    client.recv
  end
  at_exit do
    client.unsubscribe(dataref_name: dr)
    client.shutdown
  end

  trap("SIGINT") {
    exit
  }

end
