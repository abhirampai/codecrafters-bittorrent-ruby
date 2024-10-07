# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'net/http'
require 'uri'

require_relative 'bencoding'
require_relative 'bit_torrent_client'
require_relative 'tcp_connection'

# Class to handle all magnet related methods
=begin
magnet:?xt=urn:btih:d69f91e6b2ae4c542468d1073a71d4ea13879a7f&amp;dn=sample.torrent&amp;tr=http%3A%2F%2Fbittorrent-test-tracker.codecrafters.io%2Fannounce
=end
class MagnetExtension
  def self.decode(link)
    url = link[8..]
    url_params = get_query_params(url)
    url_params.each_with_object({}) do |param, hash|
      key, value = param.split('=')
      hash[key] = value
    end
  end

  def self.handshake(link)
    decoded_magnet_extension_hash = decode(link)
    info_hash = [decoded_magnet_extension_hash['xt'].gsub('urn:btih:', '')].pack('H*')

    uri = URI(CGI.unescape(decoded_magnet_extension_hash['tr']))
    uri.query = URI.encode_www_form(
      info_hash:,
      peer_id: SecureRandom.alphanumeric(20),
      port: 6881,
      uploaded: 0,
      downloaded: 0,
      left: 999,
      compact: 1
    )

    response = Net::HTTP.get(uri)
    peers = Bencoding.decode(response)['peers']
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
    payload = message[:payload][1..]
    decoded_payload = Bencoding.decode(payload)

    [decoded_magnet_extension_hash, peer_id, decoded_payload, socket]
  end

  private

  def self.get_query_params(url)
    url.split('&')
  end
end