## Accounts.sol testing scaffold

- [ ]  `Full Coverage`
- [x]  `Allowances`
    - [x]  Single option transfer between empty accounts
    - [x]  Single asset transfer using submitTransfers
        - [x]  block if msg.sender doesn’t have allowance
        - [x]  block if subId + asset allowance < amount
        - [x]  allow if allowances not enough, but ERC721 approved
        - [x]  allow if allowances not enough, but ERC721 approvedForAll
        - [x]  correct final balances post multiple transfers
    - [x]  Multi subId transfer
        - [x]  block transfer if msg.sender doesn’t have allowance for specific subId
    - [x]  Multi account / subId transfer
        - [x]  block transfer if msg.sender doesn’t have allowance for one account
    - [x]  Manager initiated transfer without allowances
    - [x]  Auto spender allowance when using `createAccount(owner, spender, _manager)`
    - [ ] Asset / subId allowances not transfered upon ownership change 
- [ ]  `submitTransfer/s()`
    - [ ]  Correct balance transfer post single transfer
    - [ ]  Correct balance transfer post 3-way transfer
- [ ]  `manager.handleAdjustment`
    - [ ]  transfer between different risk managers
    - [ ]  block unsupported asset
    - [ ]  liquidations
        - [ ]  Forceful auctions
- [ ]  `asset.handleAdjustment`
    - [ ]  positive-only USDC wrapper blocks negative adjustments
    - [ ]  positive-only USDC wrapper blocks manager from moving funds asymmetrically?
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

### Accounts gas benchmarks (possibly use hardhat or cast)
- [ ]  Gas Testing
    - [ ]  Large
        - [ ]  100x position account to transfer 50x positions out to 0 (Expiration).
        - [ ]  100x position account to transfer 50x positions out to non-zero (split).
        - [ ]  100x position account to transfer 4x positions out to non-zero (split).
        - [ ]  Add 65kth heldAsset to a 65k heldAsset.length account
    - [ ]  Small
        - [ ]  0x position account to get 10x positions
        - [x]  2x subId transfer between two 0x position accounts [275k gas]

### BONUS
- [ ]  Method where user can pass a "signature" to submitTransfers() to grant one-time allowance to spender
       This would probably be a custom method with custom data structures?
       - https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/draft-ERC20Permit.sol

