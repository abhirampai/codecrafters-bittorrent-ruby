# frozen_string_literal: true

require 'json'
require 'digest'

if ARGV.length < 2
  puts 'Usage: your_bittorrent.sh <command> <args>'
  exit(1)
end

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
      decoded_integer_value, current_index = decode_integer(bencoded_value, current_index)
      result << decoded_integer_value
    when 'e'
      return result, current_index
    when /\d/
      string_value, current_index = decode_string(bencoded_value, current_index)
      result << string_value
    else
      puts 'Only strings are supported at the moment'
      exit(1)
    end
  end
  result.size == 1 ? result[0] : result.flatten(1)
end

def encode_bencode(data)
  case data
  when String
    "#{data.length}:#{data}"
  when Integer
    "i#{data}e"
  when Array
    "l#{data.map { |item| encode_bencode(item) }.join}e"
  when Hash
    "d#{data.sort.map { |key, value| "#{encode_bencode(key)}#{encode_bencode(value)}" }.join}e"
  else
    raise "Unsupported data type: #{data.class}"
  end
end

command = ARGV[0]

if command == 'decode'
  encoded_str = ARGV[1]
  decoded_str = decode_bencode(encoded_str)
  puts JSON.generate(decoded_str)
end

if command == 'info'
  file = File.open(ARGV[1], 'rb')
  decoded_str = decode_bencode(file.read)
  bencoded_data = encode_bencode(decoded_str['info'])
  sha1_hash = Digest::SHA1.hexdigest(bencoded_data)

  puts "Tracker URL: #{decoded_str['announce']}"
  puts "Length: #{decoded_str['info']['length']}"
  puts "Info Hash: #{sha1_hash}"
  puts "Piece Length: #{decoded_str['info']['piece length']}"
  puts "Piece Hashes: #{decoded_str['info']['pieces'].unpack1('H*')}"
end
