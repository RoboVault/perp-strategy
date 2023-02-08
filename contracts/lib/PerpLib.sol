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

    event InitialDeposited(uint256 tokenId);
    event Deposited(
        uint256 tokenId,
        uint256 token0Balance,
        uint256 token1Balance,
        uint256 refund0,
        uint256 refund1
    );
    event Withdraw(uint256 tokenId, uint256 liquidity);
    event Destroy(uint256 tokenId, uint256 liquidity);
    event Rebalanced(uint256 tokenId, int24 _tickLower, int24 _tickUpper);
    event ExecutionResult(bool success, bytes result);

    IUniswapV3PositionsNFT public constant nftManager =
        IUniswapV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    struct positionInfo {
        IUniswapV3Pool pool;
        int24 tick_lower;
        int24 tick_upper;
        uint24 twapTime;
        int24 tickRangeMultiplier;
        address owner;
    }

    //uint256[] tokenIds;
    //mapping(uint256 => positionInfo) positions;
    address constant uniswapV3Factory =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    IERC721 constant nft = IERC721(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ISwapRouter constant router = ISwapRouter(address(0));
    address constant admin = address(0);

    //address public newAdmin = address(0);
    //constructor(address _router, address _admin) public {
    //router = ISwapRouter(_router);
    //    admin = _admin;
    //}

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

    function getLiquidity(uint256 _tokenId)
        public
        view
        returns (uint128 _liquidity)
    {
        (, , , , , , , _liquidity, , , , ) = nftManager.positions(_tokenId);
        return _liquidity;
    }

    function getLpReserves(uint256 _tokenId)
        external
        view
        returns (uint256 _token0, uint256 _token1)
    {
        /*
        uint128 _liquidity = uint128(getLiquidity(_tokenId)); //TODO: Is this cast safe?
        positionInfo memory pos = positions[_tokenId];
        (uint160 sqrtPriceX96, , , , , , ) = pos.pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(pos.tick_lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(pos.tick_upper);

        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                _liquidity
            );
            */
    }

    function getCurrentTick(uint256 _tokenId)
        external
        view
        returns (int24 tick)
    {
        /*
        positionInfo memory pos = positions[_tokenId];
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pos.pool.slot0();
        return currentTick;
        */
    }

    function getLowerTick(uint256 _tokenId) external view returns (int24 tick) {
        /*
        positionInfo memory pos = positions[_tokenId];
        return pos.tick_lower;
        */
    }

    function getUpperTick(uint256 _tokenId) external view returns (int24 tick) {
        /*
        positionInfo memory pos = positions[_tokenId];
        return pos.tick_upper;
        */
    }

    function isUnbalanced(uint256 _tokenId)
        external
        view
        returns (bool _result)
    {
        // TODO: which implementation works in practice?
        /*
        (uint256 _token0, uint256 _token1) = getLpReserves(_tokenId);
        if((_token0 < 10000) || (_token1 < 10000)){
            return true;
        } 
        return false;
        */
        /*
        positionInfo memory pos = positions[_tokenId];
        // Slot0 Has the current price.
        (uint160 sqrtPriceX96, , , , , , ) = pos.pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(pos.tick_lower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(pos.tick_upper);
        if ((sqrtPriceX96 < sqrtRatioAX96) || (sqrtPriceX96 > sqrtRatioBX96)) {
            return true;
        }
        return false;
        */
    }

    function getPriceAtTick(int24 tick) public view returns (uint256) {
        uint160 sqrtRatio = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96 = getPriceX96FromSqrtPriceX96(sqrtRatio);
        return FullMath.mulDiv(priceX96, 1e18, FixedPoint96.Q96);
    }

    function getSqrtTwapX96(IUniswapV3Pool uniswapV3Pool, uint32 twapInterval)
        public
        view
        returns (uint160 sqrtPriceX96)
    {
        /*
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = uniswapV3Pool.slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) =
                uniswapV3Pool.observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval)
            );
        }
        */
    }

    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96)
        public
        pure
        returns (uint256 priceX96)
    {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    //TODO: Consider if this function could take tokenId instead of pool
    function getTwapPrice(IUniswapV3Pool _pool, uint32 _time)
        public
        view
        returns (uint256)
    {
        uint160 sqrtPriceX96 = getSqrtTwapX96(_pool, _time); // TODO: maybe use global twap time, recommended value is 60
        //return getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        uint256 priceX96 = getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        //return priceX96.mul(1e18).div(FixedPoint96.Q96)
        return FullMath.mulDiv(priceX96, 1e18, FixedPoint96.Q96);
    }

    //     //TODO: Consider if this function could take tokenId instead of pool
    // function getTwapTick(IUniswapV3Pool _pool, uint32 _time)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     uint160 sqrtPriceX96 = getSqrtTwapX96(_pool, _time); // TODO: maybe use global twap time, recommended value is 60
    //     //return getPriceX96FromSqrtPriceX96(sqrtPriceX96);
    //     uint256 priceX96 = getPriceX96FromSqrtPriceX96(sqrtPriceX96);
    //     //return priceX96.mul(1e18).div(FixedPoint96.Q96)
    //     return TickMath.getTickAtSqrtRatio(priceX96);
    // }

    // Attempt to take input tokens and balance them for the desired pool and range so they may be deposited.
    function _balanceProportion(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) internal returns (uint256 _amount0, uint256 _amount1) {
        /*
        PoolVariables.Info memory _cache;

        _cache.amount0Desired = IERC20(_pool.token0()).balanceOf(address(this));
        _cache.amount1Desired = IERC20(_pool.token1()).balanceOf(address(this));

        (uint160 sqrtPriceX96, , , , , , ) = _pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

        _cache.liquidity = uint128(
            LiquidityAmounts
                .getLiquidityForAmount0(
                sqrtRatioAX96,
                sqrtRatioBX96,
                _cache
                    .amount0Desired
            )
                .add(
                LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    _cache.amount1Desired
                )
            )
        );

        (_cache.amount0, _cache.amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            _cache.liquidity
        );

        //Determine Trade Direction
        bool _zeroForOne =
            _cache.amount0Desired > _cache.amount0 ? true : false;

        //Determine Amount to swap
        uint256 _amountSpecified =
            _zeroForOne
                ? (_cache.amount0Desired.sub(_cache.amount0))
                : (_cache.amount1Desired.sub(_cache.amount1));

        if (_amountSpecified > 0) {
            //Determine Token to swap
            address _inputToken = _zeroForOne ? _pool.token0() : _pool.token1();

            IERC20(_inputToken).safeApprove(address(router), 0);
            IERC20(_inputToken).safeApprove(address(router), _amountSpecified);

            //Swap the token imbalanced
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: _inputToken,
                    tokenOut: _zeroForOne ? _pool.token1() : _pool.token0(),
                    fee: _pool.fee(),
                    recipient: address(this),
                    amountIn: _amountSpecified,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        _amount0 = IERC20(_pool.token0()).balanceOf(address(this));
        _amount1 = IERC20(_pool.token1()).balanceOf(address(this));
        */
    }

    function getPool(
        address _token0,
        address _token1,
        uint24 _fee
    ) public view returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
                PoolAddress.computeAddress(
                    uniswapV3Factory,
                    PoolAddress.getPoolKey(
                        address(_token0),
                        address(_token1),
                        _fee
                    )
                )
            );
    }

    // TWAP time interval to observe price range.
    function setTwapTime(uint256 _tokenId, uint24 _twapTime) external {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender, "Not Owner");
        positions[_tokenId] = positionInfo(
            pos.pool,
            pos.tick_lower,
            pos.tick_upper,
            _twapTime,
            pos.tickRangeMultiplier,
            pos.owner
        );
        */
    }

    // Used to establish how many multiples of the observed price range we want to use as our target.
    function setTickRangeMultiplier(
        uint256 _tokenId,
        int24 _tickRangeMultiplier
    ) external {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender, "Not Owner");
        positions[_tokenId] = positionInfo(
            pos.pool,
            pos.tick_lower,
            pos.tick_upper,
            pos.twapTime,
            _tickRangeMultiplier,
            pos.owner
        );
        */
    }

    // This function must be called to get a token ID for deposit().
    struct positionParameters {
        address _token0;
        address _token1;
        uint256 _amount0;
        uint256 _amount1;
        uint24 _fee;
        uint24 _twapTime;
        int24 _tickRangeMultiplier;
        bool _balance;
    }

    function newPosition(positionParameters calldata _params)
        external
        returns (
            uint256 _tokenId,
            uint256 _refund0,
            uint256 _refund1
        )
    {
        /*
        require(_params._token0 != address(0), "Invalid Token0");
        require(_params._token1 != address(0), "Invalid Token1");
        require(_params._fee > 0, "Invalid Fee");
        require(
            _params._tickRangeMultiplier > 0,
            "Invalid Tick Range Multiplier"
        );

        if (_params._amount0 > 0)
            SafeERC20.safeTransferFrom(
                IERC20(_params._token0),
                msg.sender,
                address(this),
                _params._amount0
            );
        if (_params._amount1 > 0)
            SafeERC20.safeTransferFrom(
                IERC20(_params._token1),
                msg.sender,
                address(this),
                _params._amount1
            );

        IUniswapV3Pool pool =
            IUniswapV3Pool(
                PoolAddress.computeAddress(
                    uniswapV3Factory,
                    PoolAddress.getPoolKey(
                        _params._token0,
                        _params._token1,
                        _params._fee
                    )
                )
            );
        (int24 tickLower, int24 tickUpper) =
            determineTicks(
                pool,
                _params._twapTime,
                _params._tickRangeMultiplier
            );
        uint256 amount0Bal = _params._amount0;
        uint256 amount1Bal = _params._amount1;
        if (_params._balance) {
            (amount0Bal, amount1Bal) = _balanceProportion(
                pool,
                tickLower,
                tickUpper
            );
        }

        IERC20(_params._token0).safeApprove(address(nftManager), uint256(0));
        IERC20(_params._token1).safeApprove(address(nftManager), uint256(0));
        IERC20(_params._token0).safeApprove(address(nftManager), uint256(-1));
        IERC20(_params._token1).safeApprove(address(nftManager), uint256(-1));

        (_tokenId, , , ) = nftManager.mint(
            IUniswapV3PositionsNFT.MintParams({
                token0: _params._token0,
                token1: _params._token1,
                fee: _params._fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Bal,
                amount1Desired: amount1Bal,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );
        require(_tokenId > 0, "Invalid token ID");
        _refund0 = IERC20(pool.token0()).balanceOf(address(this));
        _refund1 = IERC20(pool.token1()).balanceOf(address(this));
        if (_refund0 > 0) {
            SafeERC20.safeTransfer(IERC20(pool.token0()), msg.sender, _refund0);
        }
        if (_refund1 > 0) {
            SafeERC20.safeTransfer(IERC20(pool.token1()), msg.sender, _refund1);
        }

        positions[_tokenId] = positionInfo(
            pool,
            tickLower,
            tickUpper,
            _params._twapTime,
            _params._tickRangeMultiplier,
            msg.sender
        );
        emit InitialDeposited(_tokenId);
        emit Deposited(_tokenId, amount0Bal, amount1Bal, _refund0, _refund1);
        //return _tokenId;
        */
    }

    // Deposit funds into uniswap position. Tokens will be balanced regardless of what is deposited.
    function deposit(
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1,
        bool _balance
    ) external returns (uint256 _refund0, uint256 _refund1) {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender, "Not Owner");

        if (_amount0 > 0)
            SafeERC20.safeTransferFrom(
                IERC20(pos.pool.token0()),
                msg.sender,
                address(this),
                _amount0
            );
        if (_amount1 > 0)
            SafeERC20.safeTransferFrom(
                IERC20(pos.pool.token1()),
                msg.sender,
                address(this),
                _amount1
            );
        uint256 token0Bal = _amount0;
        uint256 token1Bal = _amount1;
        if (_balance) {
            (token0Bal, token1Bal) = _balanceProportion(
                pos.pool,
                pos.tick_lower,
                pos.tick_upper
            );
        }

        //uint256 token0Bal = IERC20(pos.pool.token0()).balanceOf(address(this));
        //uint256 token1Bal = IERC20(pos.pool.token1()).balanceOf(address(this));

        if (token0Bal > 0 && token1Bal > 0) {
            // If the pool is out of range, it might be possible to single deposit.
            nftManager.increaseLiquidity(
                IUniswapV3PositionsNFT.IncreaseLiquidityParams({
                    tokenId: _tokenId,
                    amount0Desired: token0Bal,
                    amount1Desired: token1Bal,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                })
            );
            IUniswapV3Pool pool = IUniswapV3Pool(pos.pool);
            _refund0 = IERC20(pool.token0()).balanceOf(address(this));
            _refund1 = IERC20(pool.token1()).balanceOf(address(this));
            if (_refund0 > 0) {
                SafeERC20.safeTransfer(
                    IERC20(pool.token0()),
                    msg.sender,
                    _refund0
                );
            }
            if (_refund1 > 0) {
                SafeERC20.safeTransfer(
                    IERC20(pool.token1()),
                    msg.sender,
                    _refund1
                );
            }
            emit Deposited(_tokenId, token0Bal, token1Bal, _refund0, _refund1);
        }
        */
    }

    /*
    function _deposit(uint256 _tokenId) internal returns (uint256 _refund0, uint256 _refund1) {

    }
    */

    // This should destroy old position NFT and create a new one with a new range.
    function rebalance(uint256 _currentId) external returns (uint256 _tokenId) {
        /*
        positionInfo memory pos = positions[_currentId];
        require(pos.owner == msg.sender, "Not Owner");
        _destroyPosition(_currentId);

        (int24 tickLower, int24 tickUpper) =
            determineTicks(pos.pool, pos.twapTime, pos.tickRangeMultiplier);
        (uint256 amount0Desired, uint256 amount1Desired) =
            _balanceProportion(pos.pool, tickLower, tickUpper);

        (_tokenId, , , ) = nftManager.mint(
            IUniswapV3PositionsNFT.MintParams({
                token0: pos.pool.token0(),
                token1: pos.pool.token1(),
                fee: pos.pool.fee(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );
        require(_tokenId > 0, "Invalid token ID");
        //Record updated information.
        delete positions[_currentId];
        positions[_tokenId] = positionInfo(
            pos.pool,
            tickLower,
            tickUpper,
            pos.twapTime,
            pos.tickRangeMultiplier,
            pos.owner
        );
        emit Rebalanced(_tokenId, tickLower, tickUpper);
        */
    }

    // Position owner may withdraw all funds from any position at any time. Position will not be destroyed.
    function withdraw(uint256 _tokenId, uint128 _liquidity) external {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender, "Not Owner");
        _withdraw(_tokenId, _liquidity);
        _sweepTokens(_tokenId);
        emit Withdraw(_tokenId, _liquidity);
        */
    }

    function _withdraw(uint256 _tokenId, uint128 _liquidity) internal {
        (uint256 liqAmt0, uint256 liqAmt1) = nftManager.decreaseLiquidity(
            IUniswapV3PositionsNFT.DecreaseLiquidityParams({
                tokenId: _tokenId,
                liquidity: _liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            })
        );

        // This has to be done after DecreaseLiquidity to collect the tokens we
        // decreased and the fees at the same time.
        nftManager.collect(
            IUniswapV3PositionsNFT.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        /*
        positionInfo memory pos = positions[_tokenId];
        nftManager.sweepToken(pos.pool.token0(), 0, address(this));
        nftManager.sweepToken(pos.pool.token1(), 0, address(this));
        */
    }

    function destroyPosition(uint256 _tokenId) public {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender, "Not Owner");
        _destroyPosition(_tokenId);
        _sweepTokens(_tokenId);
        */
    }

    // Send user the contract balance
    function _sweepTokens(uint256 _tokenId) internal {
        /*
        positionInfo memory pos = positions[_tokenId];
        IERC20 token0 = IERC20(pos.pool.token0());
        IERC20 token1 = IERC20(pos.pool.token1());
        if (token0.balanceOf(address(this)) > 0) {
            token0.safeTransfer(pos.owner, token0.balanceOf(address(this)));
        }
        if (token1.balanceOf(address(this)) > 0) {
            token1.safeTransfer(pos.owner, token1.balanceOf(address(this)));
        }
        */
    }

    function _destroyPosition(uint256 _tokenId) internal {
        (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(
            _tokenId
        );
        _withdraw(_tokenId, liquidity);
        nftManager.burn(_tokenId);
        emit Destroy(_tokenId, liquidity);
    }

    function collectPositionFees(uint256 _tokenId) public {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender, "Not Owner");
        
        nftManager.collect(
            IUniswapV3PositionsNFT.CollectParams({
                tokenId: _tokenId,
                recipient: pos.owner,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        */
    }

    // For emergencies only! This will brick the strategies using the position!
    function sweepNFT(address _to, uint256 _tokenId) external {
        /*
        positionInfo memory pos = positions[_tokenId];
        require(pos.owner == msg.sender || admin == msg.sender, "Not Owner");
        */
        nft.safeTransferFrom(address(this), _to, _tokenId);
    }

    // This has been put into the contract in the unlikely event of a breaking change in uniswap.
    // To be used if sweepNFT doesnt do the trick.
    function exec(address _target, bytes memory _data) external {
        require(admin == msg.sender, "Not Administrator");
        // Make the function call
        (bool success, bytes memory result) = _target.call(_data);

        // success is false if the call reverts, true otherwise
        require(success, "Call failed");

        // result contains whatever has returned the function
        emit ExecutionResult(success, result);
    }
    /*
    function changeAdmin(address _admin) external {
        require(admin == msg.sender, "Not Administrator");
        newAdmin = _admin;
    }

    function acceptAdmin() external {
        require(newAdmin == msg.sender, "Not new Administrator");
        admin = newAdmin;
        newAdmin = address(0);
    }
*/
}
