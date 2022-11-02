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

contract SignedVolQuote {
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

  // mock quotes
  // assume the signer must be the fromAcc
  // assume price > 0 => fromAcc receives $ equal to price
  struct QuoteData {
    uint fromAcc;
    uint toAcc;
    TransferData transfer;
    PricingData bid;
    PricingData ask;
    uint deadline;
    uint nonce;
    address quoteAddr; // if quoter version changes (redeploy), must ensure old messages cant be re-ran
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

  function volQuoteToPrice(CallerArgs memory callerArgs, QuoteData memory quote) 
  external view
  returns (int price) {
    PricingData memory pricing = callerArgs.isBuying ? quote.ask : quote.bid;
    return _volQuoteToPrice(quote.transfer, pricing);
  }

  function executeSignature(CallerArgs memory callerArgs, QuoteData memory quote, Signature memory sig) external {
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

    PricingData memory pricing = callerArgs.isBuying ? quote.ask : quote.bid;
    int price = _volQuoteToPrice(quote.transfer, pricing);
    require(callerArgs.isBuying ? (price < callerArgs.limitPrice) : (price > callerArgs.limitPrice)); 

    AccountStructs.AssetTransfer[] memory netTransfer = new AccountStructs.AssetTransfer[](2);

    netTransfer[0] = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: callerArgs.toAcc,
      asset: IAsset(address(quote.transfer.asset)),
      subId: quote.transfer.subId,
      amount: quote.transfer.amount,
      assetData: bytes32(0)
    });

    netTransfer[1] = AccountStructs.AssetTransfer({
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