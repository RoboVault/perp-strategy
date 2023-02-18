// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import {SafeERC20, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IUniswapV2Router01.sol";
import "../interfaces/IERC721.sol";
import {IStrategyInsurance} from "../StrategyInsurance.sol";
import "./PoolVariables.sol";
import {PoolAddress} from "@uniswap-periphery/contracts/libraries/PoolAddress.sol";
import {ISwapRouter} from "@uniswap-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
//import "./OracleLibrary.sol";
import "./SafeUint128.sol";
import "../interfaces/IUniswapV3PositionsNFT.sol";

library PerpLib {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SafeMath for uint8;
    using PoolVariables for IUniswapV3Pool;

    event ExecutionResult(bool success, bytes result);

    function determineTicks(
        IUniswapV3Pool _pool,
        uint24 _twapTime,
        int24 tickRangeMultiplier
    ) public view returns (int24, int24) {
        int24 tickSpacing = _pool.tickSpacing();
        int24 baseThreshold = tickSpacing * tickRangeMultiplier;
        if (_twapTime > 0) {
            uint32[] memory _observeTime = new uint32[](2);
            _observeTime[0] = _twapTime;
            _observeTime[1] = 0;
            (int56[] memory _cumulativeTicks, ) = _pool.observe(_observeTime);
            int56 _averageTick = (_cumulativeTicks[1] - _cumulativeTicks[0]) /
                int24(_twapTime);
            return
                PoolVariables.baseTicks(
                    int24(_averageTick),
                    baseThreshold,
                    tickSpacing
                );
        } else {
            (, int24 tick, , , , , ) = _pool.slot0();
            return PoolVariables.baseTicks(tick, baseThreshold, tickSpacing);
        }
    }

    // This has been put into the contract in the unlikely event of a breaking change in uniswap.
    // To be used if sweepNFT doesnt do the trick.
    function exec(address _target, bytes memory _data) external {
        // Make the function call
        (bool success, bytes memory result) = _target.call(_data);

        // success is false if the call reverts, true otherwise
        require(success, "Call failed");

        // result contains whatever has returned the function
        emit ExecutionResult(success, result);
    }
}
