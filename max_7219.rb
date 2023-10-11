require 'denko'

module Denko
  module LED
    class Max7219 < Denko::SPI::BitBang
      include Denko::SPI::Peripheral

      attr_reader :device_count

      MODE_B = {
        '0' => 0x00,
        '1' => 0x01,
        '2' => 0x02,
        '3' => 0x03,
        '4' => 0x04,
        '5' => 0x05,
        '6' => 0x06,
        '7' => 0x07,
        '8' => 0x08,
        '9' => 0x09,
        '-' => 0x0A,
        'E' => 0x0B,
        'H' => 0x0C,
        'L' => 0x0D,
        'P' => 0x0E,
        ' ' => 0x0F
      }

      def before_initialize(options={})
        options[:pin] = 10
        super(options)
      end

      def after_initialize(options={})
        super(options)

        @device_count = options.fetch(:device_count, 1)
      end

      def enable_defaults(address)
        set_intensity(address, 1)
        decode_mode(address, 0xFF)
        scan_limit(address)
        enable(address)
      end

      def enable(address)
        send(address, 0x0C, 1)
      end

      def disable(address)
        send(address, 0x0C, 0)
      end

      def print(address, string, padchar=" ")
        enable_defaults(0)
        font = MODE_B
        extra = string.scan('.').size
        chars = string.rjust(8+extra, padchar).split('')
        offset = 0
        has_period = false
        chars.reverse.each_with_index do |char, i| 
          if char == "."
            offset+=1
            has_period = true
          else
            font_char = font.fetch(char, 0x0F)
            font_char = font_char | 0b10000000 if has_period
            set_digit(address, i+1-offset, font_char, false)
            has_period = false
          end
        end
      end

      def set_digit(address, digit, value, decimal_point=false)
        return if digit > 8 || digit < 1
        value = value | 0x80 if decimal_point
        send(address, digit, value)
      end

      def set_intensity(address, level)
        return if level < 0
        return if level > 15

        send(address, 0x0A, level)
      end

      def decode_mode(address, value)
        return unless [0, 1, 15, 255].include?(value)

        send(address, 0x09, value)
      end

      def scan_limit(address, limit=7)
        limit = 3 if limit < 3
        limit = 7 if limit > 7
        send(address, 0x0B, limit)
      end

      def display_test(address)
        send(address, 0x0F, 1)
      end

      def display_normal(address)
        send(address, 0x0F, 0)
      end

      private

      def send(address, opcode, data)
        return if address >= device_count

        write_data = Array.new(device_count*2, 0)
        offset = address * 2
        write_data[offset] = opcode
        write_data[offset+1] = data
        transfer(pin, write: write_data)
      end
    end
  end
end

