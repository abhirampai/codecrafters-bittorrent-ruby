# frozen_string_literal: true

require 'json'
require 'digest'
require 'uri'
require 'net/http'

require_relative 'bencoding'
require_relative 'tcp_connection'

# Handles cli related methods
class BitTorrentClient
  def self.decode(encoded_str)
    decoded = Bencoding.decode(encoded_str)
    puts JSON.generate(decoded)
  end

  def self.info(file_path)
    decoded_file = decode_file(file_path)
    decoded_info = decoded_file['info']
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
end
