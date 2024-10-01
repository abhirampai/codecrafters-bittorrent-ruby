# frozen_string_literal: true

require 'json'

if ARGV.length < 2
  puts 'Usage: your_bittorrent.sh <command> <args>'
  exit(1)
end

def decode_bencode(bencoded_value)
  result = []
  current_index = 0
  length = bencoded_value.length

  while current_index < length
    case bencoded_value[current_index]
    when 'd'
      current_index += 1
      decoded_value, end_index = decode_bencode(bencoded_value[current_index..])
      current_index += end_index + 1
      result << Hash[decoded_value.each_slice(2).to_a]
    when 'l'
      current_index += 1
      decoded_array, end_index = decode_bencode(bencoded_value[current_index..])
      current_index += end_index + 1
      result << decoded_array
    when 'i'
      current_index += 1
      index_of_e = bencoded_value.index('e', current_index)
      decoded_integer_value = bencoded_value[current_index..index_of_e].to_i
      current_index = index_of_e + 1
      result << decoded_integer_value
    when 'e'
      return result, current_index
    when /\d/
      colon_index = bencoded_value.index(':', current_index)
      string_length = bencoded_value[current_index...colon_index].to_i
      current_index = colon_index + 1
      string_value = bencoded_value[current_index...(current_index + string_length)]
      current_index += string_length
      result << string_value
    else
      puts 'Only strings are supported at the moment'
      exit(1)
    end
  end
  result.size == 1 ? result[0] : result.flatten(1)
end

command = ARGV[0]

if command == 'decode'
  encoded_str = ARGV[1]
  decoded_str = decode_bencode(encoded_str)
  puts JSON.generate(decoded_str)
end
