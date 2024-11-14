// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {Currency} from "v4-core/types/Currency.sol";

contract TakeProfitsHooks is BaseHook, ERC1155 {
    mapping(PoolId poolId => int24 lastTick) public lastTicks;

    mapping(uint256 positionId => uint256 outputClaimable)
        public claimableOutputToken;
    mapping(uint256 positionId => uint256 claimsSupply) public claimTokenSupply;

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
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // sender should not be this hook
        if (sender == address(this)) return (this.afterSwap.selector, 0);

        // the logic to fulfill order starts here

        return (this.afterSwap.selector, 0);
    }

    // external functions for the core hook
    function placeOrder(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmount
    ) external returns (int24) {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);

        uint256 positionId = getPositionId(key, tick, zeroForOne);

        claimTokenSupply[positionId] += inputAmount;
        _mint(msg.sender, positionId, inputAmount, "");

        address sellToken = zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);

        IERC20(sellToken).transferFrom(msg.sender, address(this), inputAmount);

        return tick;
    }

    function cancelOrder() external {}

    function redeem() external {}

    // core order execution funcitons

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
