# frozen_string_literal: true
require 'httparty'

class MempoolSpaceApiClient
  include HTTParty
  base_uri 'https://mempool.space/signet/api'

  def self.utxos(address)
    response = get("/address/#{address}/utxo")
    if response.success?
      JSON.parse(response.body)
    else
      abort "Failed to fetch UTXOs"
    end
  end

  def self.utxos_details(utxos)
    utxos.map do |utxo|
      tx_response = get("/tx/#{utxo['txid']}")
      abort "Failed to fetch TX #{utxo['txid']}" unless tx_response.success?
      tx_data = JSON.parse(tx_response.body)

      vout = tx_data['vout'][utxo['vout']]
      {
        txid: utxo['txid'],
        vout: utxo['vout'],
        value: utxo['value'],
        scriptpubkey: vout['scriptpubkey']
      }
    end
  end

  def self.broadcast_transaction(transaction)
    hex = transaction.to_hex
    response = post('/tx', body: hex)

    if response.success?
      response.body
    else
      abort "Transaction failed: #{response.body}"
    end
  end
end
