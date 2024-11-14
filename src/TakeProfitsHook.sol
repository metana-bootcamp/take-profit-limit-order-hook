// SPDX-License-Idenfier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract TakeProfitsHook is BaseHook, ERC1155 {
    mapping(PoolId poolId => int24 lastTick) public lastTicks;

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
        address sender, // address that initialized the swap
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // if sender is hook
        if (sender == address(this)) return (this.afterSwap.selector, 0);
        bool tryMore = true;
        while (tryMore) {}
        return (this.afterSwap.selector, 0);
    }

    function placeOrder() external returns (int24){}

    function cancelOrder() external {}

    function redeem() external {}

    function tryExecutingOrder() internal returns (bool tryMore, int24 newTick) {}

    function executeOrder() internal {}

    function swapAndSettleBalances() internal returns(BalanceDelta) {}

    function _settle() internal {}
}
