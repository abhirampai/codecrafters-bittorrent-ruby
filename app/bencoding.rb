# frozen_string_literal: true

# Handles bencoding related methods
class Bencoding
  class << self
    def decode(bencoded_value) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
      result = []
      current_index = 0
      length = bencoded_value.length

      while current_index < length
        case bencoded_value[current_index]
        when 'd'
          current_index += 1
          decoded_value, end_index = decode(bencoded_value[current_index..])
          current_index += end_index + 1
          result << Hash[decoded_value.each_slice(2).to_a]
        when 'l'
          current_index += 1
          decoded_array, end_index = decode(bencoded_value[current_index..])
          current_index += end_index + 1
          result << decoded_array
        when 'i'
          current_index += 1
          decoded_integer_value, current_index = decode_integer(bencoded_value, current_index)
          result << decoded_integer_value
        when 'e'
          return result, current_index
        when /\d/
          string_value, current_index = decode_string(bencoded_value, current_index)
          result << string_value
        else
          puts 'Unsupported format'
          exit 1
        end
      end
      result.size == 1 ? result[0] : result.flatten(1)
    end

    def encode(data) # rubocop:disable Metrics/MethodLength
      case data
      when String
        "#{data.length}:#{data}"
      when Integer
        "i#{data}e"
      when Array
        "l#{data.map { |item| encode(item) }.join}e"
      when Hash
        "d#{data.sort.map { |key, value| "#{encode(key)}#{encode(value)}" }.join}e"
      else
        raise "Unsupported data type: #{data.class}"
      end
    end

    private

    def decode_integer(input, current_index)
      end_index = input.index('e', current_index)
      decoded_integer_value = input[current_index..end_index].to_i
      [decoded_integer_value, end_index + 1]
    end

    def decode_string(input, current_index)
      colon_index = input.index(':', current_index)
      string_length = input[current_index...colon_index].to_i
      current_index = colon_index + 1
      string_value = input[current_index...(current_index + string_length)]
      current_index += string_length
      [string_value, current_index]
    end
  end
end
