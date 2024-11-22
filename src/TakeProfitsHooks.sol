// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {Currency} from "v4-core/types/Currency.sol";

contract TakeProfitsHooks is BaseHook, ERC1155 {
    using StateLibrary for IPoolManager;

    // poolid => tickToSellAt => zeroForOne => inputAmount
    mapping(PoolId poolId => mapping(int24 tickToSellAt => mapping(bool zeroForOne => uint256 inputAmount)))
        public pendingOrders;

    mapping(PoolId poolId => int24 lastTick) public lastTicks;

    mapping(uint256 positionId => uint256 outputClaimable)
        public claimableOutputToken;
    mapping(uint256 positionId => uint256 claimsSupply)
        public claimTokensSupply;

    // errors
    error NotEnoughToClaim();

    constructor(
        IPoolManager _manager,
        string memory _uri
    ) BaseHook(_manager) ERC1155(_uri) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) external override returns (bytes4) {
        lastTicks[key.toId()] = tick;
        return this.afterInitialize.selector;
    }

    function afterSwap(
        address sender, // address of the caller who initiated the swap
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // sender should not be this hook
        if (sender == address(this)) return (this.afterSwap.selector, 0);

        // should we try to find and execute orders? True initially
        bool tryMore = true;
        int24 currentTick;

        while (tryMore) {
            // Try executing pending orders for this pool

            // `tryMore` is true if we successfully found and executed an order
            // which shifted the tick value
            // and therefore we need to look again if there are any pending orders
            // within new tick range

            // `tickAfterExecutingOrder` is tick value of the pool
            // after executing order
            // if no order was executed, `tickAfterExecutingOrder` will be
            // same as current tick and `tryMore` as false

            (tryMore, currentTick) = tryExecutingOrders(
                key,
                !params.zeroForOne
            );
        }

        // new last known tick for this pool is the tick value
        lastTicks[key.toId()] = currentTick;

        return (this.afterSwap.selector, 0);
    }

    // external functions for the core hook
    // create an order
    function placeOrder(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmount
    ) external returns (int24) {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 positionId = getPositionId(key, tick, zeroForOne);

        // create a pending order
        pendingOrders[key.toId()][tick][zeroForOne] += inputAmount;

        claimTokensSupply[positionId] += inputAmount;
        _mint(msg.sender, positionId, inputAmount, "");

        address sellToken = zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);

        IERC20(sellToken).transferFrom(msg.sender, address(this), inputAmount);

        return tick;
    }

    // cancel or modify
    function cancelOrder(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 amountToCancel
    ) external {
        // get lower actually usable ticj for their order
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 positionId = getPositionId(key, tick, zeroForOne);

        // Check how many claim tokens they have for this position
        uint256 positionTokens = balanceOf(msg.sender, positionId);
        if (positionTokens < amountToCancel) revert NotEnoughToClaim();

        // remove their `amountToCancel` worth of position from pending orders
        pendingOrders[key.toId()][tick][zeroForOne] -= amountToCancel;

        // reduce claim token total supply and burn there share
        claimTokensSupply[positionId] -= amountToCancel;
        _burn(msg.sender, positionId, amountToCancel);

        // Send them their input token
        Currency token = zeroForOne ? key.currency0 : key.currency1;
        token.transfer(msg.sender, amountToCancel);
    }

    function redeem() external {}

    // core order execution functions

    function tryExecutingOrders(
        PoolKey calldata key,
        bool executeZeroForOne
    ) internal returns (bool tryMore, int24 newTick) {
        (, int24 currentTick, , ) = poolManager.getSlot0(key.toId());
        int24 lastTick = lastTicks[key.toId()];

        // Given `currentTick` and `lastTick` , 2 cases possible :

        // Case (1) - Tick has increased, i.e. `currentTick` > `lastTick`
        // Case (2) - TIck has decreased i.e. `currentTick` < `lastTick`

        // If tick increases => Token ) price has increased
        // => We should check if we have orders looking to sell Token 0
        // i.e. orders that have zeroForOne = true

        // --------
        // Case (1)
        // --------

        // Tick has increased i.e. people bought Token0 by selling 1
        // i.e. Token0 price going up
        // e.g. in an ETH/USDC pool, people are buying ETH for USDC causing ETH price to increase
        // We should check if we have any orders looking to sell Token 0
        // at ticks `lastTick` to `currentTick`
        // i.e. check if we have any orders to sell ETH at new price that ETH is at now because of the increase

        if (currentTick > lastTick) {
            executeOrder();
        }
        // --------
        // Case (2)
        // --------
        // Tick has gown down i.e. people bough Token 1 by selling Token0
        // i.e. Token 1 price has increased
        // e.g. in an ETH/USDC pool, people are selling ETH for USDC causing ETH price to decrease (and USDC to increase)
        // We should check if we have any orders looking to sell Token 1
        // at ticks `currentTick` to `lastTick`
        // i.e. check if we have any orders to buy ETH at new price that ETH is at now because of the decrease
        else {
            executeOrder();
        }
    }

    function executeOrder() internal {}

    // view function

    function getPositionId(
        PoolKey calldata key,
        int24 tick,
        bool zeroForOne
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(key.toId(), tick, zeroForOne)));
    }

    function getLowerUsableTick(
        int24 tick,
        int24 tickSpacing
    ) private pure returns (int24) {
        int24 intervals = tick / tickSpacing;

        if (tick < 0 && tick % tickSpacing != 0) intervals--; // round towards negavtive inifinity

        return intervals * tickSpacing;
    }
}
