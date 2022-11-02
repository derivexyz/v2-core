pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "../interfaces/IAsset.sol";
import "../interfaces/IManager.sol";
import "../Allowances.sol";
import "../libraries/ArrayLib.sol";
import "../libraries/AssetDeltaLib.sol";
import "../Account.sol";
import "../libraries/BlackScholesV2.sol";
import "test/account/mocks/assets/OptionToken.sol";
import "test/account/mocks/assets/lending/Lending.sol";

contract SignedVolComboQuote {
  using BlackScholesV2 for BlackScholesV2.Black76Inputs;
  // can be put in a vector to represent a combo
  struct TransferData {
    address asset;
    uint96 subId;
    int amount;
  }

  /**
   * set of BS parameters to use when the quote is executed
   * when client executes the quote, the contract would calculate Black76 option price using these params
   * strike price and time-to-expiry are taken from the contract/SubID definition
   * @param volatility Implied volatility over the period til expiry as a percentage
   * TODO if TransferData is a vector, volatility can be presented as a vector to price spreads 
   * @param fwdSpread the additive spread (fwd = spotOracle + fwdSpread) to use in Black76 
   * @param discount the discounting factor to use in Black76
   */
  struct PricingData {
    uint128 volatility;
    int128 fwdSpread;
    uint64 discount;
  }

  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  /**
   * A quote signed by a market maker
   * @param fromAcc MM's account (signature expected to come from the owner of fromAcc)
   * @param toAcc 0 if the quote can be claimed by anyone, else a specific account
   * @param transfers an array of TransferData defining a combo (can have length 1 for a single option trade)
   * @param bids if the taker is selling, bids pricing data will be used to price the combo (using live spot)
   * @param asks if the taker is buing, asks pricing data will be used to price the combo (using live spot)
   * @param deadline reverts if block.timestamp >= deadline
   * @param nonce MM can specify a noonce if they want to write multiple identical quotes and expect several fills
   * @param quoteAddr the quoter contract address that the message is meant for
   */
  struct QuoteComboData {
    uint fromAcc;
    uint toAcc;
    TransferData[] transfers;
    PricingData[] bids;
    PricingData[] asks;
    uint deadline;
    uint nonce;
    address quoteAddr;
  }

  struct CallerArgs {
    uint toAcc;
    bool isBuying; // if true, MM's ask quote will be used, else bid is used
    int limitPrice;
  }

  Account account;
  OptionToken immutable optionToken;
  IAsset immutable cashAsset;
  address owner = msg.sender;
  uint128 spotOracleMock = 1500e18;

  mapping(bytes32 => bool) usedNonces;

  constructor(Account _account, address _cashAsset, address _optionToken) {
    account = _account;
    optionToken = OptionToken(_optionToken);
    cashAsset = IAsset(_cashAsset);
  }

  function volComboQuoteToPrice(CallerArgs memory callerArgs, QuoteComboData memory quote) 
  external view
  returns (int price) {
    PricingData[] memory pricings = callerArgs.isBuying ? quote.asks : quote.bids;
    return _volComboQuoteToPrice(quote.transfers, pricings);
  }

  function executeSignature(CallerArgs memory callerArgs, QuoteComboData memory quote, Signature memory sig) external {
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
    require((callerArgs.toAcc == quote.toAcc) || (quote.toAcc == uint(0))); 
    // check that the caller actually owns the toAcc they claim
    require(msg.sender == account.ownerOf(callerArgs.toAcc));
    // TODO to protect MMs, may want to allow quote pulling (via a separate tx)
    // also, deadline may need to be capped by some reasonable number
    // e.g. if quote.deadline - block.timestamp > 1 hour (some const), maybe revert?
    // or could allow a msg cancel request
    require(block.timestamp < quote.deadline);

    require(quote.quoteAddr == address(this));

    PricingData[] memory pricings = callerArgs.isBuying ? quote.asks : quote.bids;
    int price = _volComboQuoteToPrice(quote.transfers, pricings);
    require(callerArgs.isBuying ? (price < callerArgs.limitPrice) : (price > callerArgs.limitPrice)); 

    AccountStructs.AssetTransfer[] memory netTransfer = new AccountStructs.AssetTransfer[](1 + quote.transfers.length);
    for (uint i = 0; i < quote.transfers.length; i++)
    {
      netTransfer[i] = AccountStructs.AssetTransfer({
        fromAcc: fromAcc,
        toAcc: callerArgs.toAcc,
        asset: IAsset(address(quote.transfers[i].asset)),
        subId: quote.transfers[i].subId,
        amount: quote.transfers[i].amount,
        assetData: bytes32(0)
      });
    }

    netTransfer[quote.transfers.length] = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: callerArgs.toAcc,
      asset: cashAsset,
      subId: 0,
      amount: -price,
      assetData: bytes32(0)
    });

    usedNonces[message] = true;
    account.submitTransfers(netTransfer, "");
  }

  function _volComboQuoteToPrice(TransferData[] memory transfers, PricingData[] memory pricings)
  internal view
  returns (int)
  {
    require(transfers.length == pricings.length);
    int price = 0;
    for (uint i; i < transfers.length; i++){
      price += _volQuoteToPrice(transfers[i], pricings[i]);
    }
    return price;
  }

  function _volQuoteToPrice(TransferData memory transfer, PricingData memory pricing)
  internal view
  returns (int)
  {
    require(address(transfer.asset) == address(optionToken));
    (uint strikePrice, uint expiry, bool isCall) = optionToken.subIdToListing(transfer.subId);
    int128 fwd = int128(spotOracleMock) + pricing.fwdSpread;
    BlackScholesV2.Black76Inputs memory b76Input = BlackScholesV2.Black76Inputs({
    timeToExpirySec: uint64(expiry - block.timestamp),
    volatilityDecimal: pricing.volatility,
    fwdDecimal: (fwd > 0) ? uint128(fwd) : uint128(1),
    strikePriceDecimal: uint128(strikePrice),
    discountDecimal: pricing.discount
  });
    (uint callPrice, uint putPrice) = BlackScholesV2.pricesBlack76(b76Input);
    int price = isCall ? int(callPrice) : int(putPrice);
    return price * transfer.amount / 1e18;
  }

  /// builds a prefixed hash to mimic the behavior of eth_sign.
  function prefixed(bytes32 hash) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
  }

  
}