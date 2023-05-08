// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IMarginAsset {
  function getValue(uint amount, uint spotShock, uint volShock) external view returns (uint value, uint confidence);
}
