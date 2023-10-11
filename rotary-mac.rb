#
# Example using a rotary encoder to control audio output volume on a Mac.
#
require 'bundler/setup'
require 'denko'
require 'forwardable'
require_relative './max_7219'
require_relative 'xp-client'

dr = "sim/cockpit2/radios/actuators/com2_standby_frequency_hz"
client = XplaneController::Client.new

com2_freq_khz = nil

# Arduino Board
board = Denko::Board.new(Denko::Connection::Serial.new)

# KD2-22 Button wired to button released pin
button = Denko::DigitalIO::Button.new(board: board, pin: 41, pullup: true)

# Plain LED
led = Denko::LED.new(board: board, pin: 22)

# Max7219
display = Denko::LED::Max7219.new(board: board, pin: 10, pins: { clock: 11, output: 12 }, device_count: 1)
display.enable_defaults(0)

client.subscribe(dataref_name: dr) do |v|
  if com2_freq_khz != v
    com2_freq_khz = v
    display.print(0, sprintf("%.3f", (v / 100)))
  end
end

# encoder
encoder = Denko::DigitalIO::RotaryEncoder.new(board: board, pins: { clock: 3, data: 2 }, divider: 1, steps_per_revolution: 30)
encoder_button = Denko::DigitalIO::Button.new(board: board, pin: 4, pullup: true)

encoder_dr = "sim/cockpit2/radios/actuators/com2_standby_frequency_Mhz"
encoder_step = 1000
encoder_button.up do
  if encoder_dr.end_with?("_khz")
    encoder_dr = "sim/cockpit2/radios/actuators/com2_standby_frequency_Mhz"
    encoder_step = 1000
  else
    encoder_dr = "sim/cockpit2/radios/actuators/com2_standby_frequency_khz"
    encoder_step = 10
  end
end

encoder.add_callback do |update|
  value = (((com2_freq_khz&.to_i||11800) * 10) + (update[:change] * encoder_step))
  high, low = value.divmod(1000)
  high = 136 if high < 118
  high = 118 if high > 136
  send_value = encoder_step == 1000 ? high : low
  client.set_dataref(encoder_dr, send_value)
end

button.up do
  puts "Button released!"
  led.toggle
end

loop do
  client.recv
end

at_exit {
  client.unsubscribe(dataref_name: dr)
  display.disable(0)
}

trap("SIGINT") {
  exit
}

sleep
