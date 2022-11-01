// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "./DynamicArrayLib.sol";
import "./LinkedListLib.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/IAccount.sol";
import "../interfaces/IAsset.sol";
import "../../test/shared/mocks/MockAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "test/account/mocks/assets/OptionToken.sol";

contract CommitmentLinkedList {
  using DynamicArrayLib for uint96[];
  using LinkedListLib for SortedList;
  using SafeCast for uint128;

  error NotExecutable();
  error AlreadyCommitted();
  error Registered();
  error NotRegistered();
  error BadInputLength();

  struct Commitment {
    uint16 bidVol;
    uint16 askVol;
    uint32 bidStakerIndex;
    uint32 askStakerIndex;
    uint64 weight;
    uint64 timestamp;
  }

  struct FinalizedQuote {
    uint16 bestVol;
    uint64 weight;
  }

  struct StakerInfo {
    uint64 stakerId;
    uint64 nonce;
    uint128 totalDeposit; // todo: can probably reduce to one word
    uint128 depositLeft;
    uint accountId;
  }

  // sorted list sorting vol from low to high
  // for bid: we go from end to find the highest
  // for ask: we go from head to find the lowest
  struct SortedList {
    mapping(uint16 => VolNode) nodes;
    uint16 length;
    uint16 head;
    uint16 end;
  }

  struct VolNode {
    uint16 vol;
    uint16 prev;
    uint16 next;
    uint64 totalWeight;
    uint64 epoch;
    bool initialized;
    Stake[] stakes;
  }

  struct Stake {
    uint64 stakerId;
    uint64 weight;
    uint128 collateral;
  }

  struct QuoteCommitment {
    uint96 subId;
    uint16 bidVol;
    uint16 askVol;
    uint64 expiry;
    uint64 weight;
    uint64 nonce;
  }
  // uint128 maxCollat; // specify max collat?

  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // only 0 ~ 1 is used
  // pending/collecting => subid => queue
  mapping(uint8 => mapping(uint96 => SortedList)) public bidQueues;
  mapping(uint8 => mapping(uint96 => SortedList)) public askQueues;

  /// @dev pending/collecting => subid
  mapping(uint8 => uint96[]) public subIds;

  /// @dev epoch => subId => stakerId => Commitment
  mapping(uint64 => mapping(uint96 => mapping(uint64 => Commitment))) public commitments;

  // subId => [] total lengths of queue;
  uint32[2] public length;

  mapping(address => StakerInfo) public stakers;

  mapping(uint64 => address) public stakerAddresses;

  uint64 currentId = 0;

  mapping(uint96 => FinalizedQuote) public bestFinalizedBids;
  mapping(uint96 => FinalizedQuote) public bestFinalizedAsks;

  uint8 public COLLECTING = 1;
  uint8 public PENDING = 0;
  uint public MAX_GAS_COST = 1e18; // $1
  uint public TOLERANCE = 5e16; // 5%
  uint public spotPrice = 1500e18; // todo: connect to spot oracle

  uint64 public collectingEpoch = 1;
  uint64 public pendingEpoch = 0;

  uint64 pendingStartTimestamp;
  uint64 collectingStartTimestamp;

  address immutable quote;
  address immutable quoteAsset;
  OptionToken immutable optionToken;
  address immutable account;
  address immutable manager;

  constructor(address _account, address _quote, address _quoteAsset, address _optionToken, address _manager) {
    account = _account;
    quoteAsset = _quoteAsset;
    optionToken = OptionToken(_optionToken);
    quote = _quote;
    manager = _manager;
    IERC20(_quote).approve(quoteAsset, type(uint).max);
  }

  // ============================================
  //                 View functions
  // ============================================

  function pendingLength() external view returns (uint) {
    return length[PENDING];
  }

  function collectingLength() external view returns (uint) {
    return length[COLLECTING];
  }

  function pendingBidListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = bidQueues[PENDING][subId].head;
    end = bidQueues[PENDING][subId].end;
    length_ = bidQueues[PENDING][subId].length;
  }

  function pendingAskListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = askQueues[PENDING][subId].head;
    end = askQueues[PENDING][subId].end;
    length_ = bidQueues[PENDING][subId].length;
  }

  function pendingBestBidAsk(uint96 subId) external view returns (
    uint16 bestBid, uint64 bidWeight, uint16 bestAsk, uint64 askWeight
  ) {
    uint16 end = bidQueues[PENDING][subId].end;
    VolNode memory bidNode = bidQueues[PENDING][subId].nodes[end];
    bidWeight = bidNode.totalWeight;
    bestBid = bidNode.vol;

    uint16 head = askQueues[PENDING][subId].head;
    VolNode memory askNode = askQueues[PENDING][subId].nodes[head];
    askWeight = askNode.totalWeight;
    bestAsk = askNode.vol;
  }

  function collectingBidListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = bidQueues[COLLECTING][subId].head;
    end = bidQueues[COLLECTING][subId].end;
    length_ = bidQueues[COLLECTING][subId].length;
  }

  function collectingAskListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = askQueues[COLLECTING][subId].head;
    end = askQueues[COLLECTING][subId].end;
    length_ = askQueues[COLLECTING][subId].length;
  }

  // ============================================
  //                 Setup Staker
  // ============================================

  function register() external returns (uint64 stakerId) {
    if (stakers[msg.sender].stakerId != 0) revert Registered();

    stakerId = ++currentId;

    // create accountId and
    uint accountId = IAccount(account).createAccount(address(this), IManager(manager));

    stakers[msg.sender] = StakerInfo(stakerId, 0, 0, 0, accountId);
    stakerAddresses[stakerId] = msg.sender;
  }

  function deposit(uint128 amount) external {
    if (stakers[msg.sender].stakerId == 0) revert NotRegistered();
    IERC20(quote).transferFrom(msg.sender, address(this), amount);
    MockAsset(quoteAsset).deposit(stakers[msg.sender].accountId, 0, amount);

    stakers[msg.sender].totalDeposit += amount;
    stakers[msg.sender].depositLeft += amount;
  }

  // ============================================
  //                 Submit Commits
  // ============================================

  /// @dev commit to the 'collecting' block
  function commit(uint96 subId, uint16 bidVol, uint16 askVol, uint64 weight) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint128 collatToLock = _addCommitToQueue(cacheCOLLECTING, stakers[msg.sender].stakerId, subId, bidVol, askVol, weight);
    stakers[msg.sender].depositLeft = stakers[msg.sender].totalDeposit - collatToLock;

    length[cacheCOLLECTING] += 1;

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  function commitMultiple(
    uint96[] calldata _subIds,
    uint16[] calldata _bidVols,
    uint16[] calldata _askVols,
    uint64[] calldata _weights
  ) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint _length = _subIds.length;
    if (_bidVols.length != _length || _askVols.length != _length || _weights.length != _length) revert BadInputLength();

    uint128 collatToLock;
    for (uint i = 0; i < _length; i++) {
      collatToLock += _addCommitToQueue(
        cacheCOLLECTING, stakers[msg.sender].stakerId, _subIds[i], _bidVols[i], _askVols[i], _weights[i]
      );
    }

    // auto-clears deposits from old epochs
    // todo: block multiple deposits per epoch
    stakers[msg.sender].depositLeft = stakers[msg.sender].totalDeposit - collatToLock;

    length[cacheCOLLECTING] += uint8(_length);

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  ///@dev commit on behalf of an market maker by signature
  function commitOnBehalf(address signer, QuoteCommitment memory _quote, Signature memory sig) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    _verifyQuote(_quote, sig, signer);

    // todo: support multiple commitments (currently clears depositLeft)
    uint128 collatToLock = _addCommitToQueue(
      cacheCOLLECTING, stakers[signer].stakerId, _quote.subId, _quote.bidVol, _quote.askVol, _quote.weight
    );

    stakers[signer].depositLeft = stakers[signer].totalDeposit - collatToLock;
    length[cacheCOLLECTING] += 1;

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  // ============================================
  //                 Execute Commits
  // ============================================

  /// @dev commit to the 'collecting' block
  function executeCommit(uint executorAccount, uint96 subId, bool isBid, uint16 vol, uint64 weight) external {
    // check account Id is from message.sender
    require(IAccount(account).ownerOf(executorAccount) == msg.sender, "auth");

    _checkRollover();

    uint premiumPerUnit = _getUnitPremium(vol, subId);

    // cache variable to avoid stack too deep when trying to access subId later
    mapping(uint64 => Commitment) storage stakerCommits = commitments[pendingEpoch][subId];

    if (isBid) {
      // update storage
      SortedList storage list = bidQueues[PENDING][subId];
      (Stake[] memory counterParties, uint numCounterParties) = list.removeWeightFromVolList(vol, weight);
      SortedList storage askList = askQueues[PENDING][subId];

      // trade with counter parties
      AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](numCounterParties * 2);
      for (uint i; i < numCounterParties; i++) {
        if (counterParties[i].weight == 0) return;

        {
          StakerInfo storage staker = stakers[stakerAddresses[counterParties[i].stakerId]];

          // remove binding ask from the same "counter party"
          askList.removeStakerWeight(
            stakerCommits[counterParties[i].stakerId].askVol,
            counterParties[i].weight,
            stakerCommits[counterParties[i].stakerId].askStakerIndex
          );

          // paid option from executor to node
          transferBatch[2 * i] = AccountStructs.AssetTransfer({
            fromAcc: executorAccount,
            toAcc: staker.accountId,
            asset: IAsset(address(optionToken)),
            subId: subId,
            amount: int(uint(counterParties[i].weight)),
            assetData: bytes32(0)
          });
          // paid premium from staker to executor
          transferBatch[2 * i + 1] = AccountStructs.AssetTransfer({
            fromAcc: staker.accountId,
            toAcc: executorAccount,
            asset: IAsset(quoteAsset),
            subId: 0,
            amount: int(uint(premiumPerUnit * counterParties[i].weight)),
            assetData: bytes32(0)
          });

          /* premium sent to executor */
          staker.totalDeposit -= SafeCast.toUint128(premiumPerUnit * counterParties[i].weight);
        }
      }
      IAccount(account).submitTransfers(transferBatch, "");
    } else {
      // update storage
      SortedList storage list = askQueues[PENDING][subId];
      (Stake[] memory counterParties, uint numCounterParties) = list.removeWeightFromVolList(vol, weight);

      // used to remove linked bids
      SortedList storage bidList = bidQueues[PENDING][subId];

      // trade with counter parties
      AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](numCounterParties * 2);
      for (uint i; i < numCounterParties; i++) {
        if (counterParties[i].weight == 0) return;
        StakerInfo storage staker = stakers[stakerAddresses[counterParties[i].stakerId]];

        bidList.removeStakerWeight(
          stakerCommits[counterParties[i].stakerId].bidVol,
          counterParties[i].weight,
          stakerCommits[counterParties[i].stakerId].bidStakerIndex
        );

        // paid option from staker to executor
        transferBatch[2 * i] = AccountStructs.AssetTransfer({
          fromAcc: staker.accountId,
          toAcc: executorAccount,
          asset: IAsset(address(optionToken)),
          subId: subId,
          amount: int(uint(counterParties[i].weight)),
          assetData: bytes32(0)
        });
        // paid premium from executor to staker
        transferBatch[2 * i + 1] = AccountStructs.AssetTransfer({
          fromAcc: executorAccount,
          toAcc: staker.accountId,
          asset: IAsset(quoteAsset),
          subId: 0,
          amount: int(uint(premiumPerUnit * counterParties[i].weight)),
          assetData: bytes32(0)
        });

        /* collateral now used to cover short */
        staker.totalDeposit -= counterParties[i].collateral;
      }
      IAccount(account).submitTransfers(transferBatch, "");
    }
  }

  // ============================================
  //                  Life cycle
  // ============================================
  function checkRollover() external {
    _checkRollover();
  }

  ///@dev used to make a quote invalid
  function increaseNonce(uint64 _amountToIncrease) external {
    stakers[msg.sender].nonce += _amountToIncrease;
  }

  // ============================================
  //               Internal Functions
  // ============================================

  function _addCommitToQueue(
    uint8 cacheCOLLECTING,
    uint64 stakerId,
    uint96 subId,
    uint16 bidVol,
    uint16 askVol,
    uint64 weight
  ) internal returns (uint128 collat) {
    if (commitments[collectingEpoch][subId][stakerId].timestamp != 0) revert AlreadyCommitted();
    subIds[cacheCOLLECTING].addUniqueToArray(subId);

    // take max of bid / ask collat sine both are removed upon execution
    collat = getCollatLockUp(weight, subId, bidVol, askVol);

    // add to both bid and ask queue with the same collateral
    // using COLLECTING instead of cache because of stack too deep
    uint bidStakerIndex =
      bidQueues[COLLECTING][subId].addStakerToLinkedList(bidVol, weight, collat, stakerId, collectingEpoch);
    uint askStakerIndex =
      askQueues[COLLECTING][subId].addStakerToLinkedList(askVol, weight, collat, stakerId, collectingEpoch);

    // add to commitment array
    commitments[collectingEpoch][subId][stakerId] =
      Commitment(bidVol, askVol, uint32(bidStakerIndex), uint32(askStakerIndex), weight, uint64(block.timestamp));
  }

  function _getUnitPremium(uint16 vol, uint96 subId) internal view returns (uint) {
    // todo: spot needs to be dynamic
    return uint(optionToken.getValue(uint(subId), 1e18, spotPrice, uint(vol) * 1e16));
  }

  function getCollatLockUp(uint64 weight, uint96 subId, uint16 bidVol, uint16 askVol) public view returns (uint128) {
    uint16 bidPremium = SafeCast.toUint16(_getUnitPremium(bidVol, subId) / 1e18);
    uint16 askPremium = SafeCast.toUint16(_getUnitPremium(askVol, subId) / 1e18);
    uint128 bidCollat = _getBidLockUp(weight, subId, bidPremium);
    uint128 askCollat = _getAskLockUp(weight, subId, askPremium);
    return (askCollat > bidCollat) ? askCollat : bidCollat;
  }

  function _verifyQuote(QuoteCommitment memory _quote, Signature memory sig, address signer) internal view {
    // verify signature
    bytes32 message = _prefixed(keccak256(abi.encode(_quote)));
    require(ecrecover(message, sig.v, sig.r, sig.s) == signer, "!signer");

    // verify signer is a staker in the system
    require(stakers[signer].stakerId != 0, "!staker");

    // verify nonce. Won't increase
    require(_quote.nonce > stakers[signer].nonce, "nonce");

    // verify expiry
    // todo: make sure expiry > next pending end
    require(_quote.expiry > block.timestamp + 5 minutes, "expiring");
  }

  // todo: change this to EIP712 signature
  function _prefixed(bytes32 hash) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
  }

  function _getBidLockUp(uint64 weight, uint96, /*subId*/ uint16 bid) internal view returns (uint128) {
    return SafeCast.toUint128(_getContractsToLock(bid) * uint(weight) * uint(bid));
  }

  function _getAskLockUp(uint64 weight, uint96, /*subId*/ uint16 ask) internal view returns (uint128) {
    uint contracts = _getContractsToLock(ask);
    return SafeCast.toUint128(contracts * (uint(weight) * spotPrice / 1e18 * 2e17) / 1e18);
  }

  function _getContractsToLock(uint16 bidOrAsk) internal view returns (uint) {
    return (MAX_GAS_COST * 1e18) / (uint(bidOrAsk) * TOLERANCE);
  }

  function _checkRollover() internal returns (uint8 newPENDING, uint8 newCOLLECTING) {
    // Commitment[256] storage pendingQueue = queue[PENDING];

    (uint8 cachePENDING, uint8 cacheCOLLECTING) = (PENDING, COLLECTING);

    /// if no pending: check we need to put collecting to pending
    if (pendingStartTimestamp == 0 || length[cachePENDING] == 0) {
      if (collectingStartTimestamp != 0 && block.timestamp - collectingStartTimestamp > 5 minutes) {
        // console2.log("roll over! change pending vs collecting");
        (cachePENDING, cacheCOLLECTING) = _rollOverCollecting(cachePENDING, cacheCOLLECTING);
        return (cachePENDING, cacheCOLLECTING);
      }
    }

    // nothing pending and there are something in the collecting phase:
    // make sure oldest one is older than 5 minutes, if so, move collecting => pending
    if (length[cachePENDING] > 0) {
      // console2.log("check if need to update finalized");
      if (block.timestamp - pendingStartTimestamp < 5 minutes) return (cachePENDING, cacheCOLLECTING);

      _updateFromPendingForEachSubId(cachePENDING);
      // console2.log("roll over! already update pending => finalized");
      (cachePENDING, cacheCOLLECTING) = _rollOverCollecting(cachePENDING, cacheCOLLECTING);
    }

    return (cachePENDING, cacheCOLLECTING);
  }

  function _rollOverCollecting(uint8 cachePENDING, uint8 cacheCOLLECTING)
    internal
    returns (uint8 newPENDING, uint8 newCOLLECTING)
  {
    (COLLECTING, PENDING) = (cachePENDING, cacheCOLLECTING);

    pendingStartTimestamp = uint64(block.timestamp);

    // dont override the array with 0. just reset length
    delete length[cachePENDING]; // delete the length for "new collecting"

    // roll both collecting and pending epoch.
    collectingEpoch += 1;
    pendingEpoch += 1;

    return (cacheCOLLECTING, cachePENDING);
  }

  function _updateFromPendingForEachSubId(uint8 _indexPENDING) internal {
    uint96[] memory subIds_ = subIds[_indexPENDING];

    for (uint i; i < subIds_.length; i++) {
      uint96 subId = subIds_[i];
      SortedList storage bidList = bidQueues[_indexPENDING][subId];

      SortedList storage askList = askQueues[_indexPENDING][subId];

      // return head of bid
      if (bidList.end != 0) {
        bestFinalizedBids[subId] = FinalizedQuote(bidList.end, askList.nodes[askList.end].totalWeight);
      }

      if (askList.head != 0) {
        bestFinalizedAsks[subId] = FinalizedQuote(askList.head, askList.nodes[askList.head].totalWeight);
      }

      bidList.clearList();
      askList.clearList();
    }
  }
}
