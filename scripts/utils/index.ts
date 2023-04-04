import {ethers} from "hardhat";


export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

export function toBN(val: string, decimals?: number) {
  decimals = decimals || 18;
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
