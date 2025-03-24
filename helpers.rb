# frozen_string_literal: true

module Helpers
  def key_path
    @key_path ||= File.join(__dir__, 'wallet', 'key.dat')
  end

  def satoshis_to_btc(sat)
    sat.to_f / 100_000_000
  end

  def btc_to_satoshis(btc)
    (btc * 100_000_000).to_i
  end
end
