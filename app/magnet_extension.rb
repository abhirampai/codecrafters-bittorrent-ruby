
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

  private

  def self.get_query_params(url)
    url.split('&')
  end
end