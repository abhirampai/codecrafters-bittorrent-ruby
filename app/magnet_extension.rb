# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'net/http'
require 'uri'

require_relative 'bencoding'
require_relative 'bit_torrent_client'
require_relative 'tcp_connection'

# Class to handle all magnet related methods
class MagnetExtension
  class << self
    def decode(link)
      url = link[8..]
      url_params = get_query_params(url)
      url_params.each_with_object({}) do |param, hash|
        key, value = param.split('=')
        hash[key] = value
      end
    end

    def handshake(link) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      decoded_magnet_extension_hash = decode(link)
      info_hash = [decoded_magnet_extension_hash['xt'].gsub('urn:btih:', '')].pack('H*')

      peers = BitTorrentClient.find_peers(CGI.unescape(decoded_magnet_extension_hash['tr']), info_hash)
      peer_ip, peer_port = BitTorrentClient.decode_peers(peers).last.split(':')

      socket = TCPConnection.handshake(peer_ip, peer_port, info_hash, extension: true)

      socket_response = socket.read(68)
      _, _, reserved_bytes, _, peer_id = socket_response.unpack('C A19 A8 A20 H*')

      return unless reserved_bytes.unpack1('H*').to_i(16).positive?

      TCPConnection.read_until(socket, 5)
      extension_handshake_message = Bencoding.encode({ 'm' => { 'ut_metadata' => 16 } })
      length = [2 + extension_handshake_message.bytesize].pack('N')
      socket.write(length + [20].pack('C') + [0].pack('C') + extension_handshake_message)

      message = TCPConnection.read_until(socket, 20)
      decoded_payload = Bencoding.decode(message[:payload][1..])

      [decoded_magnet_extension_hash, peer_id, decoded_payload, socket]
    end

    def request_metadata(magnet_link, piece_index = 0) # rubocop:disable Metrics/AbcSize
      decoded_magnet_extension_hash, _, decoded_payload, socket = MagnetExtension.handshake(magnet_link)
      request_payload = Bencoding.encode({ 'msg_type' => 0, 'piece' => piece_index })
      length = [2 + request_payload.bytesize].pack('N')
      socket.write(length + [20].pack('C') + [decoded_payload['m']['ut_metadata']].pack('C') + request_payload)

      message = TCPConnection.read_until(socket, 20)
      decoded_info = Bencoding.decode(message[:payload][1..])[1]
      socket.close

      sha1_hash = decoded_magnet_extension_hash['xt'].gsub('urn:btih:', '')
      [CGI.unescape(decoded_magnet_extension_hash['tr']), [sha1_hash].pack('H*'), decoded_info, sha1_hash]
    end

    private

    def get_query_params(url)
      url.split('&')
    end
  end
end
