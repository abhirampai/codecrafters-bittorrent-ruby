# frozen_string_literal: true

require_relative 'bit_torrent_client'

if ARGV.length < 2
  puts 'Usage: your_bittorrent.sh <command> <args>'
  exit(1)
end

command = ARGV[0]
args = ARGV[1..]

case command
when 'decode'
  BitTorrentClient.decode(args[0])
when 'info'
  BitTorrentClient.info(args[0])
when 'peers'
  BitTorrentClient.peers(args[0])
when 'handshake'
  BitTorrentClient.handshake(args[0], args[1])
when 'download_piece'
  if args.length < 4 || args[0] != '-o'
    puts 'Usage: your_bittorrent.sh download_piece -o <output_file> <torrent_file> <piece_index>'
    exit(1)
  end
  BitTorrentClient.download_piece(args[1], args[2], args[3])
when 'download'
  if args.length < 3 || args[0] != '-o'
    puts 'Usage: your_bittorrent.sh download -o <output_file> <torrent_file>'
    exit(1)
  end
  BitTorrentClient.download(args[1], args[2])
when 'magnet_parse'
  BitTorrentClient.parse_magnet_link(args[0])
when 'magnet_handshake'
  BitTorrentClient.magnet_handshake(args[0])
when 'magnet_info'
  BitTorrentClient.magnet_info(args[0])
when 'magnet_download_piece'
  BitTorrentClient.magnet_download_piece(args[1], args[2], args[3])
when 'magnet_download'
  BitTorrentClient.magnet_download(args[1], args[2])
else
  puts 'Invalid command'
end
