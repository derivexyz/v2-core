import {ethers} from "hardhat";
import {BigNumber, ContractTransaction} from "ethers";


export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
export const DAY_SEC = 86400;
export const WEEK_SEC = 604800;
export const YEAR_SEC = 31536000;

export const EMPTY_BYTES = ethers.utils.hexZeroPad("0x", 32);

export function toBN(val: string, decimals: number = 18) {
  // multiplier is to handle decimals
  if (val.includes('e')) {
    if (parseFloat(val) > 1) {
      const x = val.split('.');
      const y = x[1].split('e+');
      const exponent = parseFloat(y[1]);
      const newVal = x[0] + y[0] + '0'.repeat(exponent - y[0].length);
      console.warn(`Warning: toBN of val with exponent, converting to string. (${val}) converted to (${newVal})`);
      val = newVal;
    } else {
      console.warn(
        `Warning: toBN of val with exponent, converting to float. (${val}) converted to (${parseFloat(val).toFixed(
          decimals,
        )})`,
      );
      val = parseFloat(val).toFixed(decimals);
    }
  } else if (val.includes('.') && val.split('.')[1].length > decimals) {
    console.warn(`Warning: toBN of val with more than ${decimals} decimals. Stripping excess. (${val})`);
    const x = val.split('.');
    x[1] = x[1].slice(0, decimals);
    val = x[0] + '.' + x[1];
  }
  return ethers.utils.parseUnits(val, decimals);
}

export function fromBN(val: BigNumber, decimals: number = 18): string {
  return ethers.utils.formatUnits(val, decimals);
}

export function toBytes32(msg: string): string {
  return ethers.utils.formatBytes32String(msg);
}

export async function findEvent(tx: ContractTransaction, eventName: string) {
  const events = (await tx.wait()).events;
  const res = events.filter((e) => e.event === eventName);
  if (res.length == 0) {
    throw Error("No event found")
  } else if (res.length > 1) {
    throw Error("Multiple events found")
  }
  return res[0].args;
}