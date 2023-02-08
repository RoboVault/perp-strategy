// SPDX-License-Identifier: MIT
pragma solidity ^0.8;
pragma experimental ABIEncoderV2;

import "../../CoreStrategyPerp.sol";
import {
    SafeERC20,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WETHPERP is CoreStrategyPerp {
    using SafeERC20 for IERC20;
    uint256 constant farmPid = 0;

    constructor(address _vault)
        CoreStrategyPerp(
            _vault,
            CoreStrategyPerpConfig(
                0x7F5c764cBc14f9669B88837ca1490cCa17c31607, // want -> USDC 
                0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB, // short -> VETH
                0xE6Df0BB08e5A97b40B21950a0A51b94c4DbA0Ff6, // router
                1e4, //mindeploy
                0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60, // Perp Vault
                0x82ac2CE43e33683c58BE4cDc40975E73aA50f459, // Perp clearingHouse
                0xd5820eE0F55205f6cdE8BB0647072143b3060067, // Perp MarketRegistery
                0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB, // vETH
                200,                                        // Tick Range Multiplier
                0                                           // Twap Time
            )
        )
    {}

    function balancePendingHarvest() public view override returns (uint256) {
        // uint256 pending =
        //     IZipRewards(farmMasterChef)
        //         .pendingReward(farmPid, address(this))
        //         .add(farmToken.balanceOf(address(this)));
        // uint256 harvestLp_A = farmToken.balanceOf(address(farmTokenLP));
        // uint256 shortLP_A = _getShortInHarvestLp();
        // uint256 totalShort = pending.mul(shortLP_A).div(harvestLp_A);
        // (uint256 wantLP_B, uint256 shortLP_B) = getLpReserves();
        // return totalShort.mul(wantLP_B).div(shortLP_B);
    }

    function _pendingRewards() internal view returns (uint256) {
        return 0; // TODO
    }

    function _depositLp() internal {
        // uint256 lpBalance = wantShortLP.balanceOf(address(this));

        // IZipRewards(farmMasterChef).deposit(
        //     farmPid,
        //     uint128(lpBalance),
        //     address(this)
        // );
    }

    function _withdrawFarm(uint256 _amount) internal {
        //TODO PERP
    }

    function claimHarvest() internal override {
        // TODO PERP
    }

    function countLpPooled() internal view override returns (uint256) {
        // TODO PERP
    }

    function _farmPendingRewards(uint256 _pid, address _user) internal view override returns (uint256) {
        return 0;
    }
}
