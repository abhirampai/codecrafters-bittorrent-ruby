# frozen_string_literal: true

require 'json'
require 'digest'
require 'uri'
require 'net/http'
require 'async'
require 'cgi'

require_relative 'bencoding'
require_relative 'tcp_connection'
require_relative 'magnet_extension'

# Handles cli related methods
class BitTorrentClient
  def self.decode(encoded_str)
    decoded = Bencoding.decode(encoded_str)
    puts JSON.generate(decoded)
  end

  def self.info(file_path)
    decoded_file = decode_file(file_path)
    decoded_info = decoded_file['info']
    p decoded_info
    bencoded_data = Bencoding.encode(decoded_info)
    sha1_hash = Digest::SHA1.hexdigest(bencoded_data)

    puts "Tracker URL: #{decoded_file['announce']}"
    puts "Length: #{decoded_info['length']}"
    puts "Info Hash: #{sha1_hash}"
    puts "Piece Length: #{decoded_info['piece length']}"
    puts "Piece Hashes: #{decoded_info['pieces'].unpack1('H*')}"
  end

  def self.peers(file_path)
    decoded_file = decode_file(file_path)
    decoded_info = decoded_file['info']
    bencoded_data = Bencoding.encode(decoded_info)
    sha1_hash = Digest::SHA1.digest(bencoded_data)

    p decoded_file['announce']
    p sha1_hash

    uri = URI(decoded_file['announce'])
    uri.query = URI.encode_www_form(
      info_hash: sha1_hash,
      peer_id: SecureRandom.alphanumeric(20),
      port: 6881,
      uploaded: 0,
      downloaded: 0,
      left: decoded_info['length'],
      compact: 1
    )

    response = Net::HTTP.get(uri)
    p response
    peers = Bencoding.decode(response)['peers']
    puts decode_peers(peers)
  end

  def self.handshake(file_path, peer_info)
    decoded_info = decode_file(file_path)['info']
    bencoded_data = Bencoding.encode(decoded_info)
    sha1_hash = Digest::SHA1.digest(bencoded_data)

    peer_ip, peer_port = peer_info.split(':')
    socket = TCPConnection.handshake(peer_ip, peer_port, sha1_hash)
    response = socket.read(68)

    _, _, _, _, peer_id = response.unpack('C A19 A8 A20 H*')
    puts "Peer ID: #{peer_id}"
  end

  def self.download_piece(output_file_path, file_path, piece_index)
    decoded_file = decode_file(file_path)
    decoded_info = decoded_file['info']
    bencoded_data = Bencoding.encode(decoded_info)
    sha1_hash = Digest::SHA1.digest(bencoded_data)

    uri = URI(decoded_file['announce'])
    uri.query = URI.encode_www_form(
      info_hash: sha1_hash,
      peer_id: SecureRandom.alphanumeric(20),
      port: 6881,
      uploaded: 0,
      downloaded: 0,
      left: decoded_info['length'],
      compact: 1
    )

    response = Net::HTTP.get(uri)
    peers = Bencoding.decode(response)['peers']
    peer_ip, peer_port = decode_peers(peers).last.split(':')

    TCPConnection.handle_peer_message(peer_ip, peer_port, sha1_hash, decoded_info, piece_index.to_i, output_file_path)
  rescue StandardError => e
    puts "Error downloading piece: #{e.message}"
  end

  def self.download(output_file_path, file_path)
    decoded_file = decode_file(file_path)
    decoded_info = decoded_file['info']
    bencoded_data = Bencoding.encode(decoded_info)
    sha1_hash = Digest::SHA1.digest(bencoded_data)

    uri = URI(decoded_file['announce'])
    uri.query = URI.encode_www_form(
      info_hash: sha1_hash,
      peer_id: SecureRandom.alphanumeric(20),
      port: 6881,
      uploaded: 0,
      downloaded: 0,
      left: decoded_info['length'],
      compact: 1
    )

    total_pieces = decoded_info['length'].to_i / decoded_info['piece length'].to_i

    response = Net::HTTP.get(uri)
    peers = Bencoding.decode(response)['peers']

    work_queue = (0..total_pieces).to_a
    available_peers = []
    combined_piece_data = ''
    loop do
      available_peers = decode_peers(peers) if available_peers.empty?
      peer = available_peers.slice!(0)
      peer_ip, peer_port = peer.split(':')
      piece_index = work_queue.slice!(0)
      combined_piece_data += TCPConnection.handle_download(peer_ip, peer_port, sha1_hash, decoded_info, piece_index.to_i)

      break if work_queue.empty?
    rescue StandardError => _e
      work_queue.unshift(piece_index)
    end

    File.open(output_file_path, 'wb') { |f| f.write(combined_piece_data) }
  rescue StandardError => e
    puts "Error downloading piece: #{e.message}"
  end

  def self.parse_magnet_link(magnet_link)
    decoded_magnet_extension_hash = MagnetExtension.decode(magnet_link)

    puts "Tracker URL: #{CGI.unescape(decoded_magnet_extension_hash['tr'])}"
    puts "Info Hash: #{decoded_magnet_extension_hash['xt'].gsub('urn:btih:', '')}"
  end

  def self.magnet_handshake(magnet_link)
    _, peer_id, decoded_payload, socket = MagnetExtension.handshake(magnet_link)

    puts "Peer ID: #{peer_id}"
    puts "Peer Metadata Extension ID: #{decoded_payload['m']['ut_metadata']}"
    socket.close
  end

  def self.magnet_info(magnet_link)
    decoded_magnet_extension_hash, _, decoded_payload, socket = MagnetExtension.handshake(magnet_link)
    request_payload = Bencoding.encode({ 'msg_type' => 0, 'piece' => 0 })
    length = [2 + request_payload.bytesize].pack('N')
    socket.write(length + [20].pack('C') + [decoded_payload['m']['ut_metadata']].pack('C') + request_payload)

    message = TCPConnection.read_until(socket, 20)

    payload = Bencoding.decode(message[:payload][1..])
    decoded_info = payload[1]

    puts "Tracker URL: #{CGI.unescape(decoded_magnet_extension_hash['tr'])}"
    puts "Length: #{decoded_info['length']}"
    puts "Info Hash: #{decoded_magnet_extension_hash['xt'].gsub('urn:btih:', '')}"
    puts "Piece Length: #{decoded_info['piece length']}"
    puts "Piece Hashes: #{decoded_info['pieces'].unpack1('H*')}"
  end

  def self.magnet_download_piece(output_file_path, magnet_link, piece_index)
    decoded_magnet_extension_hash, _, decoded_payload, socket = MagnetExtension.handshake(magnet_link)
    request_payload = Bencoding.encode({ 'msg_type' => 0, 'piece' => piece_index.to_i })
    length = [2 + request_payload.bytesize].pack('N')
    socket.write(length + [20].pack('C') + [decoded_payload['m']['ut_metadata']].pack('C') + request_payload)

    message = TCPConnection.read_until(socket, 20)
    payload = Bencoding.decode(message[:payload][1..])
    decoded_info = payload[1]
    socket.close

    announce_url = CGI.unescape(decoded_magnet_extension_hash['tr'])
    sha1_hash = [decoded_magnet_extension_hash['xt'].gsub('urn:btih:', '')].pack('H*')
    peers = find_peers(announce_url, sha1_hash, decoded_info)
    peer_ip, peer_port = decode_peers(peers).last.split(':')

    puts "Dowloading piece #{piece_index.to_i}."
    TCPConnection.handle_peer_message(peer_ip, peer_port, sha1_hash, decoded_info, piece_index.to_i, output_file_path)
  end

  private

  def self.decode_file(file_path)
    File.open(file_path, 'rb') { |file| Bencoding.decode(file.read) }
  end

  def self.decode_peers(peers)
    peers.scan(/.{6}/m).map do |peer|
      ip = peer[0..3].unpack('C4').join('.')
      port = peer[4..5].unpack1('n')
      "#{ip}:#{port}"
    end
  end

  def self.find_peers(url, sha1_hash, decoded_info)
    uri = URI(url)
    uri.query = URI.encode_www_form(
      info_hash: sha1_hash,
      peer_id: SecureRandom.alphanumeric(20),
      port: 6881,
      uploaded: 0,
      downloaded: 0,
      left: decoded_info['length'],
      compact: 1
    )

    response = Net::HTTP.get(uri)
    Bencoding.decode(response)['peers']
  rescue StandardError => e
    puts "Error downloading piece: #{e.message}"
  end
end
