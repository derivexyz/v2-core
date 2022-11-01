pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "../interfaces/IAsset.sol";
import "../interfaces/IManager.sol";
import "../Allowances.sol";
import "../libraries/ArrayLib.sol";
import "../libraries/AssetDeltaLib.sol";
import "../Account.sol";

contract SignedQuote {
  // can be put in a vector to represent a combo
  struct QuoteTransfer {
    address asset;
    uint subId;
    int amount;
  }

  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // mock quotes
  // assume the signer must be the fromAcc
  // assume price > 0 => fromAcc receives $ equal to price
  struct QuoteData {
    uint fromAcc;
    uint toAcc;
    QuoteTransfer transfer;
    int price;
    uint deadline;
    uint nonce;
    address quoteAddr; // if quoter version changes (redeploy), must ensure old messages cant be re-ran
  }

  Account account;
  address owner = msg.sender;

  // maps accountID => {noonce => isUsed}
  // TODO maybe there's a better way since if I lose track of my noonces it becomes hard to recover
  // use quote data hash mapping isntead? quoteHash => bool?
  // ^ has a problem that we may want to execute same quote several times
  // typically, deadline would be different in that case
  // maybe keep noonce so that MMs can sign many of the same order if they want to?
  // can always check this contract for if there's a
  // mapping(uint256 => mapping(uint256 => bool)) usedNonces;
  mapping(bytes32 => bool) usedNonces;

  constructor(Account _account) {
    account = _account;
  }

  function executeSignature(QuoteData memory quote, Signature memory sig, uint toAcc) external {
    // figure out if the fromAcc is owned by the signer
    uint fromAcc = quote.fromAcc;
    address fromAccOwner = account.ownerOf(fromAcc);

    // this recreates the message that was signed on the client
    bytes32 message = prefixed(keccak256(abi.encode(quote)));
    // TODO make these into custom errors
    require(ecrecover(message, sig.v, sig.r, sig.s) == fromAccOwner);
    // check noonce for fromAcc
    require(!usedNonces[message]);
    // check if the quote has a named counterparty
    // TODO will someone actually have 0 as account ID? can we force it not to?
    // TODO make toAcc flexible to allow firms support whitelisted set of people?
    require((toAcc == quote.toAcc) || (quote.toAcc == uint(0)));
    // check that the caller actually owns the toAcc they claim
    require(msg.sender == account.ownerOf(toAcc));
    // TODO to protect MMs, may want to allow quote pulling (via a separate tx)
    // also, deadline may need to be capped by some reasonable number
    // e.g. if quote.deadline - block.timestamp > 1 hour (some const), maybe revert?
    require(block.timestamp < quote.deadline);

    require(quote.quoteAddr == address(this));

    usedNonces[message] = true;

    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(address(quote.transfer.asset)),
      subId: quote.transfer.subId,
      amount: quote.transfer.amount,
      assetData: bytes32(0)
    });

    account.submitTransfer(transfer, "");
    //TODO ignore price for now, not sure yet if it's best to exchange
    // it as a lending asset transfer, or wallet-to-wallet. Need some standard.
    // Probably best to use settlement asset.
    //TODO ideally should allow an array of transfers to support combos
  }

  /// builds a prefixed hash to mimic the behavior of eth_sign.
  function prefixed(bytes32 hash) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
  }
}
