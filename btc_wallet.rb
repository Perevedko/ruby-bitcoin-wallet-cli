# frozen_string_literal: true
require 'bitcoin'
require 'thor'
require 'json'
require 'bigdecimal'
require_relative 'mempool_space_api_client'
require_relative 'helpers'

Bitcoin.chain_params = :signet

class WalletCLI < Thor
  include Helpers

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
      utxos = MempoolSpaceApiClient.utxos(key.to_p2wpkh)
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

      utxos = MempoolSpaceApiClient.utxos(key.to_p2wpkh)
      total_input_sat = utxos.sum { |u| u['value'] }
      
      required_sat = amount_sat + fee_sat
      abort "Insufficient funds. Needed: #{satoshis_to_btc(required_sat)}" if total_input_sat < required_sat

      tx = build_transaction(key, utxos, address, amount_sat, fee_sat)
      txid = MempoolSpaceApiClient.broadcast_transaction(tx)
      
      puts "Sent #{amount} sBTC to #{address}"
      puts "Transaction ID: #{txid}"
    end
  end

  private

  def with_key
    abort "First generate a key with 'generate' command" unless File.exist?(key_path)

    key_data = File.read(key_path)
    yield Bitcoin::Key.from_wif(key_data)
  end

  def build_transaction(key, utxos, recipient, amount_sat, fee_sat)
    transaction = Bitcoin::Tx.new
    details = MempoolSpaceApiClient.utxos_details(utxos)
  
    add_inputs(transaction, details)
    add_outputs_and_change(key, transaction, details, recipient, amount_sat, fee_sat)
    sign(key, transaction, details)
  
    transaction
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

  def validate_address(addr)
    Bitcoin::Script.parse_from_addr(addr)
  rescue
    abort "Invalid address format"
  end
end
