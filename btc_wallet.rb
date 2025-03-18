# frozen_string_literal: true
require 'bitcoin'
require 'thor'
require 'httparty'
require 'json'
require 'bigdecimal'
require 'pry'

Bitcoin.chain_params = :signet

class WalletCLI < Thor
  include HTTParty
  base_uri 'https://mempool.space/signet/api'

  FEE = BigDecimal('0.00001')
  private_constant :FEE

  desc "generate", "Generate a new private key"
  def generate
    abort "Key already exists at #{key_path}" if File.exist?(key_path)
  
    key = Bitcoin::Key.generate(compressed: true, network: :signet)
    
    File.write(key_path, key.to_wif)
    puts "Generated new address: #{key.to_p2wpkh}"
  end

  desc "balance", "Show wallet balance"
  def balance
    with_key do |key|
      utxos = fetch_utxos(key.to_p2wpkh)
      total = utxos.sum { |u| u['value'] }
      puts "Balance: #{satoshis_to_btc(total)} sBTC, address: #{key.to_p2wpkh}"
    end
  end

  desc "send ADDRESS AMOUNT", "Send sBTC to address"
  def send(address, amount)
    with_key do |key|
      validate_address(address)
      amount_sat = btc_to_satoshis(BigDecimal(amount))
      fee_sat = btc_to_satoshis(FEE)

      utxos = fetch_utxos(key.to_p2wpkh)
      total_input_sat = utxos.sum { |u| u['value'] }
      
      required_sat = amount_sat + fee_sat
      abort "Insufficient funds. Needed: #{satoshis_to_btc(required_sat)}" if total_input_sat < required_sat

      tx = build_transaction(key, utxos, address, amount_sat, fee_sat)
      txid = broadcast_transaction(tx)
      
      puts "Sent #{amount} sBTC to #{address}"
      puts "Transaction ID: #{txid}"
    end
  end

  private

  def key_path
    @key_path ||= File.join(__dir__, 'wallet', 'key.dat')
  end

  def with_key
    abort "First generate a key with 'generate' command" unless File.exist?(key_path)

    key_data = File.read(key_path)
    yield Bitcoin::Key.from_wif(key_data)
  end

  def fetch_utxos(address)
    response = self.class.get("/address/#{address}/utxo")
    if response.success?
      JSON.parse(response.body)
    else
      abort "Failed to fetch UTXOs"
    end
  end

  def build_transaction(key, utxos, recipient, amount_sat, fee_sat)
    transaction = Bitcoin::Tx.new
    details = utxos_details(utxos)
  
    add_inputs(transaction, details)
    add_outputs_and_change(key, transaction, details, recipient, amount_sat, fee_sat)
    sign(key, transaction, details)
  
    transaction
  end

  def utxos_details(utxos)
    utxos.map do |utxo|
      tx_response = self.class.get("/tx/#{utxo['txid']}")
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

  def add_inputs(transaction, utxos_details)
    utxos_details.each do |utxo|
      transaction.inputs << Bitcoin::TxIn.new(
        out_point: Bitcoin::OutPoint.from_txid(utxo[:txid], utxo[:vout])
      )
    end
  end

  def add_outputs_and_change(key, transaction, utxos_details, recipient, amount_sat, fee_sat)
    transaction.outputs << Bitcoin::TxOut.new(
      value: amount_sat,
      script_pubkey: Bitcoin::Script.parse_from_addr(recipient)
    )

    total_input = utxos_details.sum { |u| u[:value] }
    change = total_input - amount_sat - fee_sat
    if change > 0
      transaction.outputs << Bitcoin::TxOut.new(
        value: change,
        script_pubkey: Bitcoin::Script.parse_from_addr(key.to_p2wpkh)
      )
    end
  end

  def sign(key, transaction, utxos_details)
    utxos_details.each_with_index do |utxo, index|
      script_code = Bitcoin::Script.parse_from_payload(utxo[:scriptpubkey].htb)
      sighash = transaction.sighash_for_input(
        index,
        script_code,
        sig_version: :witness_v0,
        amount: utxo[:value]
      )
      sig = key.sign(sighash) + [Bitcoin::SIGHASH_TYPE[:all]].pack('C')
      transaction.inputs[index].script_witness.stack << sig << key.pubkey.htb
    end
  end

  def broadcast_transaction(tx)
    hex = tx.to_hex
    response = self.class.post("/tx", body: hex)
    
    if response.success?
      response.body
    else
      abort "Transaction failed: #{response.body}"
    end
  end

  def validate_address(addr)
    abort "Invalid address format" unless Bitcoin::Script.parse_from_addr(addr)
  rescue
    abort "Invalid address format"
  end

  def satoshis_to_btc(sat)
    sat.to_f / 100_000_000
  end

  def btc_to_satoshis(btc)
    (btc * 100_000_000).to_i
  end
end

WalletCLI.start(ARGV)
