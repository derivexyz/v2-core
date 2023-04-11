import {SignerContext} from "../env/signerContext";
import {BigNumber, BigNumberish} from "ethers";
import {toBN} from "../index";

const UINT32_MAX = BigNumber.from('2').pow(32).sub(1);
const UINT63_MAX = BigNumber.from('2').pow(63).sub(1);

export function getOptionSubID(expiry: number, strike: BigNumber, isCall: boolean): BigNumber {
  // can support expiry up to year 2106
  if (expiry > UINT32_MAX) {
    throw "ExpiryTooLarge";
  }

  // zero expiry guaranteed to not be possible
  if (expiry == 0) {
    throw "ZeroExpiry";
  }

  // can support strike granularity down to 8 decimal points
  if (strike.mod(toBN('1', 10)) > 0) {
    throw "StrikeTooGranular";
  }

  // convert to 8 decimal points
  strike = strike.div(toBN('1', 10));

  // can support strike as high as $92,233,720,368
  if (strike.gt(UINT63_MAX)) {
    throw "StrikeTooLarge";
  }

  let shiftedStrike = strike.shl(32);
  let shiftedIsCall = (isCall ? BigNumber.from(1) : BigNumber.from(0)).shl(95);

  // TODO: test
  return BigNumber.from(expiry).or(shiftedStrike).or(shiftedIsCall);
}

export function getOptionParams(subId: BigNumberish): {
  expiry: number,
  strike: BigNumber,
  isCall: boolean
} {
  subId = BigNumber.from(subId);
  let expiry = subId.and(UINT32_MAX).toNumber();
  let strike = subId.shr(32).and(UINT63_MAX).mul(toBN('1', 10));
  let isCall = subId.shr(95).gt(0);
  return {
    expiry,
    strike,
    isCall
  }
}