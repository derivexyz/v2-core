// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @notice Based on the FluxAggregator contract
 * @notice Use this contract when you need to test
 * other contract's ability to read data from an
 * aggregator contract, but how the aggregator got
 * its answer is unimportant
 */
contract MockV3Aggregator is AggregatorV3Interface {
  uint public constant override version = 0;

  uint public latestRound;
  uint8 public override decimals;

  mapping(uint => int) public getAnswer;
  mapping(uint => uint) public getTimestamp;
  mapping(uint => uint) private getStartedAt;
  mapping(uint => uint) private getAnsweredRoundIn;

  constructor(uint8 _decimals, int _initialAnswer) {
    decimals = _decimals;
    updateRoundData(uint80(++latestRound), _initialAnswer, block.timestamp, block.timestamp, uint80(latestRound));
  }

  function updateRoundData(uint80 _roundId, int _answer, uint _timestamp, uint _startedAt, uint80 answeredInRound)
    public
  {
    latestRound = _roundId;
    getAnswer[latestRound] = _answer;
    getTimestamp[latestRound] = _timestamp;
    getStartedAt[latestRound] = _startedAt;
    getAnsweredRoundIn[latestRound] = answeredInRound;
  }

  function getRoundData(uint80 _roundId)
    external
    view
    override
    returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
  {
    return (
      _roundId,
      getAnswer[_roundId],
      getStartedAt[_roundId],
      getTimestamp[_roundId],
      uint80(getAnsweredRoundIn[_roundId])
    );
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
  {
    return (
      uint80(latestRound),
      getAnswer[latestRound],
      getStartedAt[latestRound],
      getTimestamp[latestRound],
      uint80(getAnsweredRoundIn[latestRound])
    );
  }

  function description() external pure override returns (string memory) {
    return "v0.8/tests/MockV3Aggregator.sol";
  }
}
