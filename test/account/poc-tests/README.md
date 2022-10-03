## Accounts.sol POC tests scaffold

- [ ]  `manager.handleAdjustment`
    - [ ]  block unsupported asset
    - [ ]  liquidations
        - [ ]  Forceful auctions
- [ ]  `asset.handleAdjustment`
    - [ ]  positive-only USDC wrapper blocks manager from moving funds to negative?
    - [ ]  block unsupported manager
    - [x]  socialized losses
        - [x]  Option asset ratio post socialized loss
        - [x]  Asset augment finalBalance during transfer (positive → negative?)
        - [x]  Asset ratio stays the same with trade post socialized loss
- [ ]  manager initiated `adjustBalance()`
    - [ ]  Settlement
- [ ]  asset initiated `adjustBalance()`
    - [ ]  Lending
        - [x]  accrue interest when assessing risk
        - [x]  accrue interest when adjusting balance
        - [ ]  apply socialized losses
        - [x]  Deposits / Withdrawals
    - [ ]  Positive only DAI wrapper
- [ ]  `createAccount()`
    - [ ]  increment ID properly
- [ ]  any other unique usecases in V2 roadmap?

### BONUS
- [ ]  Method where user can pass a "signature" to submitTransfers() to grant one-time allowance to spender
       This would probably be a custom method with custom data structures?
       - https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/draft-ERC20Permit.sol

