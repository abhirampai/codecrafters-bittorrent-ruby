# frozen_string_literal: true

require 'securerandom'
require 'socket'

# Handles tcp socket related methods
class TCPConnection
  def self.handshake(peer_ip, peer_port, sha1_hash, extension: false)
    initiate_connection(peer_ip, peer_port, sha1_hash, SecureRandom.alphanumeric(20), extension:)
  end

  def self.handle_peer_message(peer_ip, peer_port, sha1_hash, info, piece_index, output_file_path)
    retry_count = 0
    peer_id = SecureRandom.alphanumeric(20)
    tcp_socket = initiate_connection(peer_ip, peer_port, sha1_hash, peer_id)

    validate_handshake(tcp_socket, sha1_hash)

    read_until(tcp_socket, 5)
    send_message(tcp_socket, 2)
    read_until(tcp_socket, 1)

    piece_data = download_piece_data(tcp_socket, info, piece_index)
    validate_piece(piece_data, info, piece_index)

    File.open(output_file_path, 'wb') { |f| f.write(piece_data) }
    puts "Piece #{piece_index} downloaded to #{output_file_path}."
    tcp_socket.close
  rescue StandardError => e
    puts "Error: #{e.message}"
    return if retry_count > 2

    retry_count += 1
    handle_peer_message(peer_ip, peer_port, sha1_hash, info, piece_index, output_file_path)
  end

  def self.handle_download(peer_ip, peer_port, sha1_hash, info, piece_index)
    peer_id = SecureRandom.alphanumeric(20)
    tcp_socket = initiate_connection(peer_ip, peer_port, sha1_hash, peer_id)

    validate_handshake(tcp_socket, sha1_hash)

    read_until(tcp_socket, 5)
    send_message(tcp_socket, 2)
    read_until(tcp_socket, 1)

    piece_data = download_piece_data(tcp_socket, info, piece_index)
    validate_piece(piece_data, info, piece_index)
    p "Piece #{piece_index} downloaded."
    tcp_socket.close
    piece_data
  end

  private

  def self.initiate_connection(peer_ip, peer_port, sha1_hash, peer_id, extension: false)
    reserved_bytes = extension ? "#{"\x00" * 5}\x10#{"\x00" * 2}" : "\x00" * 8
    payload = "#{[19].pack('C')}BitTorrent protocol#{reserved_bytes}#{sha1_hash}#{peer_id}"
    socket = TCPSocket.open(peer_ip, peer_port)
    socket.write(payload)
    socket
  end

  def self.validate_handshake(socket, sha1_hash)
    response = socket.read(68)
    _, _, _, info_hash, = response.unpack('C A19 A8 A20 H*')
    raise 'Info hash mismatch' if info_hash != sha1_hash
  end

  def self.read_until(socket, id)
    loop do
      message = read_message(socket)
      return if message[:id] == id
    end
  end

  def self.read_message(socket)
    length = socket.read(4).unpack1('N')
    return { id: nil, payload: nil } if length.zero?

    id = socket.read(1).unpack1('C')
    payload = socket.read(length - 1)

    { id: id, payload: payload }
  end

  def self.send_message(socket, id, payload = '')
    length = [1 + payload.bytesize].pack('N')
    socket.write(length + [id].pack('C') + payload)
  end

  def self.download_piece_data(socket, info, piece_index)
    piece_length = info['piece length']
    total_length = info['length']
    num_pieces = info['pieces'].length / 20
    current_piece_length = piece_index < num_pieces - 1 ? piece_length : total_length - (num_pieces - 1) * piece_length

    blocks = []
    offset = 0
    while offset < current_piece_length
      length = [16 * 1024, current_piece_length - offset].min
      blocks << { index: piece_index, begin: offset, length: }
      offset += length
    end

    blocks.each do |block|
      payload = [block[:index], block[:begin], block[:length]].pack('N3')
      send_message(socket, 6, payload)
    end

    piece_buffers = {}
    received_bytes = 0

    until received_bytes >= current_piece_length
      message = read_message(socket)
      next if message[:id] != 7

      payload = message[:payload]
      index, begin_offset = payload[0, 8].unpack('N2')
      block_data = payload[8..]

      next if index != piece_index

      piece_buffers[begin_offset] = block_data
      received_bytes += block_data.length
    end

    piece_data = ''
    piece_buffers.keys.sort.each { |begin_offset| piece_data += piece_buffers[begin_offset] }
    piece_data
  end

  def self.validate_piece(piece_data, info, piece_index)
    expected_hash = info['pieces'].byteslice(piece_index * 20, 20)
    raise 'Piece hash mismatch' if Digest::SHA1.digest(piece_data) != expected_hash
  end
end
