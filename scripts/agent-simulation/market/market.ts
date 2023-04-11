import {BigNumber, BigNumberish} from "ethers";
import {execute, getLyraContract} from "../../utils/contracts/transactions";
import {SignerContext} from "../../utils/env/signerContext";
import {getOptionParams, getOptionSubID} from "../../utils/options/optionEncoding";
import {Simulation} from "../simulation";
import chalk from "chalk";
import {fromBN, toBN} from "../../utils";


export type MarketOrder = {
  accountId: BigNumberish;
  amount: BigNumber;
  pricePerOption: BigNumber;
  collateralPerOption: BigNumber;
  signature: string;
}

export type OptionBoard = {
  subId: BigNumber;
  buyOrders: MarketOrder[]; // buy at 1000, 999, 998
  sellOrders: MarketOrder[]; // sell at 1001, 1002, 1003
}

export type Trade = {
  fromAcc: BigNumberish;
  toAcc: BigNumberish;
  asset: string;
  subId: BigNumberish;
  amount: BigNumberish;
  assetData: string;
}

const NUM_WEEKLIES = 4;

const WEEK_SEC = 86400 * 7;
const FRIDAY_MOD_OFFSET = 115200

export class Market {
  adminContext: SignerContext;
  simulation: Simulation;
  optionAsset: string;
  cashAsset: string;
  boards: {[subId: string]: OptionBoard} = {};

  constructor(adminContext: SignerContext, simulation: Simulation) {
    this.adminContext = adminContext;
    this.simulation = simulation;
    this.optionAsset = getLyraContract(adminContext, 'OptionAsset').address;
    this.cashAsset = getLyraContract(adminContext, 'CashAsset').address;
  }

  async step() {
    await this.settleBoards();
    this.updateBoards()
  }

  log() {
    for (const subId of Object.keys(this.boards)) {
      const board = this.boards[subId];
      console.log(chalk.cyan(`Board ${subId}:`));
      console.log(chalk.cyan(`- Buy orders (${board.buyOrders.length}): ${board.buyOrders.map((o) => `${o.accountId} ${fromBN(o.amount)} ${fromBN(o.pricePerOption)}`)}`));
      console.log(chalk.cyan(`- Sell orders (${board.sellOrders.length}): ${board.sellOrders.map((o) => `${o.accountId} ${fromBN(o.amount)} ${fromBN(o.pricePerOption)}`)}`));
    }
  }

  async settleBoards() {
    const expiries = Object.keys(this.boards).map((subId) => getOptionParams(BigNumber.from(subId)).expiry);
    const currentTime = this.simulation.currentTime;
    for (const expiry of expiries) {
      if (currentTime > expiry) {
        console.log(chalk.red(`Settling boards for expiry ${expiry}`));
        // todo: settle board on contract, iterate over all users to settle their options
        // delete all boards which have this expiry in their subId
        for (const subId of Object.keys(this.boards)) {
          if (getOptionParams(BigNumber.from(subId)).expiry === expiry) {
            delete this.boards[subId];
          }
        }
      }
    }
  }

  updateBoards() {
    const currentTime = this.simulation.currentTime;
    // add new expiries to the boards
    const expiries = Object.keys(this.boards).map((subId) => getOptionParams(BigNumber.from(subId)).expiry);

    const newExpiries = [];
    for (let i=0; i<NUM_WEEKLIES; i++) {
      const nextFriday = this.getNextFriday(currentTime + i * WEEK_SEC);
      if (!expiries.includes(nextFriday)) {
        newExpiries.push(nextFriday);
      }
    }

    newExpiries.forEach((expiry) => {
      console.log(chalk.cyan(`Adding new expiry ${expiry}`));
      // generate new strikes around the current spot price
      const strikes = [];
      for (let i=0; i<5; i++) {
        const strike = this.simulation.spotPrice.mul(100 - (i*2-2)).div(100);
        strikes.push(strike);
      }
      console.log(chalk.cyan(`- Strikes: ${strikes.map(fromBN)}`));

      // generate new subIds for each strike
      strikes.forEach((strike) => {
        const callSubId = getOptionSubID(expiry, strike, true);
        this.boards[callSubId] = {
          subId: callSubId,
          buyOrders: [],
          sellOrders: []
        }
        const putSubId = getOptionSubID(expiry, strike, false);
        this.boards[putSubId.toString()] = {
          subId: putSubId,
          buyOrders: [],
          sellOrders: []
        }
      });
    });
  }

  getNextFriday(timestamp: number) {
    return timestamp - ((timestamp - FRIDAY_MOD_OFFSET) % WEEK_SEC) + WEEK_SEC;
  }

  placeLimitOrder(subId: string, order: MarketOrder, isBuy: boolean): Trade[] {
    return isBuy ? this._placeBuyOrder(subId, order) : this._placeSellOrder(subId, order);
  }

  _placeBuyOrder(subId: string, buyOrder: MarketOrder): Trade[] {
    let trades: Trade[] = [];

    let board = this.boards[subId];

    let remainingAmount = buyOrder.amount;
    while (board.sellOrders.length > 0 && board.sellOrders[0].pricePerOption.lt(buyOrder.pricePerOption)) {
      const sellOrder = board.sellOrders[0];
      if (remainingAmount.gte(sellOrder.amount)) {
        trades.push({
          fromAcc: sellOrder.accountId,
          toAcc: buyOrder.accountId,
          asset: this.optionAsset,
          subId: subId,
          amount: sellOrder.amount,
          assetData: "0x"
        });
        trades.push({
          fromAcc: buyOrder.accountId,
          toAcc: sellOrder.accountId,
          asset: this.cashAsset,
          subId: subId,
          amount: sellOrder.amount.mul(sellOrder.pricePerOption),
          assetData: "0x"
        });
        remainingAmount = remainingAmount.sub(sellOrder.amount);
        board.sellOrders.shift();
      } else {
        trades.push({
          fromAcc: sellOrder.accountId,
          toAcc: buyOrder.accountId,
          asset: this.optionAsset,
          subId: subId,
          amount: remainingAmount,
          assetData: "0x"
        });
        trades.push({
          fromAcc: buyOrder.accountId,
          toAcc: sellOrder.accountId,
          asset: this.cashAsset,
          subId: subId,
          amount: remainingAmount.mul(sellOrder.pricePerOption),
          assetData: "0x"
        });
        board.sellOrders[0].amount = sellOrder.amount.sub(remainingAmount);
        remainingAmount = BigNumber.from(0);
        break;
      }
    }

    // if any amount is remaining, add it to the buy order book
    if (remainingAmount.gt(0)) {
      buyOrder.amount = remainingAmount;
      board.buyOrders.push(buyOrder);
      board.buyOrders = this.boards[subId].buyOrders.sort(
        (a, b) => +(b.pricePerOption.sub(a.pricePerOption).toString())
      );
    }

    return trades;
  }

  _placeSellOrder(subId: string, sellOrder: MarketOrder): Trade[] {
    let trades: Trade[] = [];

    let board = this.boards[subId];

    let remainingAmount = sellOrder.amount;

    while (this.boards[subId].buyOrders.length > 0 && this.boards[subId].buyOrders[0].pricePerOption.gt(sellOrder.pricePerOption)) {
      const buyOrder = board.buyOrders[0];
      if (remainingAmount.gte(buyOrder.amount)) {
        trades.push({
          fromAcc: sellOrder.accountId,
          toAcc: buyOrder.accountId,
          asset: this.optionAsset,
          subId: subId,
          amount: buyOrder.amount,
          assetData: "0x"
        });
        trades.push({
          fromAcc: buyOrder.accountId,
          toAcc: sellOrder.accountId,
          asset: this.cashAsset,
          subId: subId,
          amount: buyOrder.amount.mul(buyOrder.pricePerOption),
          assetData: "0x"
        });
        remainingAmount = remainingAmount.sub(buyOrder.amount);
        this.boards[subId].buyOrders.shift();
      } else {
        trades.push({
          fromAcc: sellOrder.accountId,
          toAcc: buyOrder.accountId,
          asset: this.optionAsset,
          subId: subId,
          amount: remainingAmount,
          assetData: "0x"
        });
        trades.push({
          fromAcc: buyOrder.accountId,
          toAcc: sellOrder.accountId,
          asset: this.cashAsset,
          subId: subId,
          amount: remainingAmount.mul(buyOrder.pricePerOption),
          assetData: "0x"
        });
        this.boards[subId].buyOrders[0].amount = buyOrder.amount.sub(remainingAmount);
        remainingAmount = BigNumber.from(0);
        break;
      }
    }

    // if any amount is remaining, add it to the buy order book
    if (remainingAmount.gt(0)) {
      sellOrder.amount = remainingAmount;

      this.boards[subId].sellOrders.push(sellOrder);
      this.boards[subId].sellOrders = this.boards[subId].sellOrders.sort(
        (a, b) => +(a.pricePerOption.sub(b.pricePerOption).toString())
      );
      // TODO: insert the remaining sell order into the correct position using a binary insert
      // let low = 0;
      // let high = board.sellOrders.length - 1;
      // while (low <= high) {
      //   const mid = Math.floor((low + high) / 2);
      //   const midPrice = board.sellOrders[mid].pricePerOption;
      //   if (midPrice.lt(sellOrder.pricePerOption)) {
      //     low = mid + 1;
      //   } else if (midPrice.gt(sellOrder.pricePerOption)) {
      //     high = mid - 1;
      //   } else {
      //     board.sellOrders.splice(mid, 0, sellOrder);
      //     break;
      //   }
      // }
    }

    return trades;
  }

  clearAllOrders(accountId: BigNumberish) {
    Object.keys(this.boards).forEach((subId) => {
      const board = this.boards[subId];
      board.buyOrders = board.buyOrders.filter((order) => order.accountId !== accountId);
      board.sellOrders = board.sellOrders.filter((order) => order.accountId !== accountId);
    });
  }
}