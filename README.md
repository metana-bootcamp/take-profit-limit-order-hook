# Limit Order - Part 1

Limit Order based hook - how can we create a hook that behaves like a simple orderbook on chain and integrating is with uniswap

it is type of limit order where you can sell an asset at a price higher than its current price

if ETH is 3000 USDC,

a Take Profit order would be something like "sell 5 ETH  of mine when ETH hits 3500 USDC"

ERC20 <> ERC20

Today : building the key functionality required for 
* placing limit orders, mint ERC1155 token to show the position
* core logic for executing thise orders
* cancel orders
* withdraw / redeeem the output token that we get from executing order

### After an order is placed
* When the price is right, how do we actually execute it? How dow we do this as a part of a hook?
* How do we know, if the price is right? figuring out when to execute the order
* How do we send/ let the user redeem their output tokens from their order

Say , Pool of of tokenA and B. 
TokenA => Token0
TokenB => Token1

Current tick of the pool is 500.

The types of take profit orders that can be placed
* Sell some amount of A as A gets more valuable than B
* Sell some amount of B as B gets more valuable (A dropping in value)


### Case 1. Tick goes up even further, byond what it is right now (500)

### Case 2. Tick goes down, below what is right now (500)

### When there is change in tick value? Swap
* Alice place an order to sell some A for B when tick = 600
* Bob makes a swap on the pool to buy A for B, that will increase the tick. New tick is 700, say
* Inside the `afterSwap` hook function, we can see that tick just shifted from 500 to 700 due to Bob's swap
* Check if there are any TP order placed in the opp direction in the range that tick just shifted and we'll find
Alice's order over there
* Now we can execute Alice's order as requirements are met.