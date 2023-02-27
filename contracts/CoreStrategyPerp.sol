// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.8.15;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/perp/IVault.sol";
import "./interfaces/perp/IBaseToken.sol";
import "./interfaces/perp/IClearingHouseConfig.sol";
import "./interfaces/perp/IAccountBalance.sol";
import "./interfaces/perp/IOrderBook.sol";
import {IClearingHouse} from "./interfaces/perp/IClearingHouse.sol";
import "./interfaces/perp/IExchange.sol";
import "./interfaces/perp/IMarketRegistry.sol";
import "./lib/PerpMath.sol";
import {IStrategyInsurance} from "./StrategyInsurance.sol";
import "./lib/PerpLib.sol";
//import "./lib/LiquidityAmounts.sol";

//TODO PERP add custom parameters: what leverage? When to rebalace? Etc
struct CoreStrategyPerpConfig {
    address want;
    address short;
    uint256 minDeploy;
    uint256 minProfit;
    // PERP
    address perpVault;
    //address clearingHouse;
    address marketRegistery;
    address baseToken;
    int24 tickRangeMultiplier;
    uint24 twapTime;
    uint256 debtMultiple;
}

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

abstract contract CoreStrategyPerp is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SafeMath for uint8;

    event DebtRebalance(
        uint256 indexed debtRatio,
        uint256 indexed swapAmount,
        uint256 indexed slippage
    );
    event CollatRebalance(
        uint256 indexed collatRatio,
        uint256 indexed adjAmount
    );
    event Debug(uint256 indexed debug1, uint256 indexed debug2);

    uint256 public collatUpper = 5100;
    uint256 public collatLower = 4900;
    uint256 public debtUpper = 10100;
    uint256 public debtMultiple = 10000;
    uint256 public debtLower = 9900;
    //uint256 public rebalancePercent = 10000; // 100% (how far does rebalance of debt move towards 100% from threshold)

    // protocal limits & upper, target and lower thresholds for ratio of debt to collateral
    uint256 public collatLimit = 7500;

    // ERC20 Tokens;
    IERC20 public short;
    uint8 wantDecimals;
    uint8 shortDecimals;
    // Contract Interfaces
    IStrategyInsurance public insurance;

    uint256 public slippageAdj = 9900; // 99%

    uint256 constant BASIS_PRECISION = 10000;

    uint256 constant STD_PRECISION = 1e18;
    address weth;
    uint256 public minDeploy;
    uint256 public minProfit;
    IVault public perpVault;
    IClearingHouse public clearingHouse;
    IOrderBook public orderBook;
    IMarketRegistry public marketRegistery;
    IBaseToken public baseToken;
    int24 public tickRangeMultiplier;
    //uint256 public totalLiquidity = 0;
    int24 public lowerTick = 0;
    int24 public upperTick = 0;
    uint24 public twapTime;

    constructor(address _vault, CoreStrategyPerpConfig memory _config)
        BaseStrategy(_vault)
    {
        // initialise token interfaces
        short = IERC20(_config.short);
        wantDecimals = IERC20Extended(_config.want).decimals();
        shortDecimals = IERC20Extended(_config.short).decimals();

        // initialize other interfaces
        maxReportDelay = 21600;
        minReportDelay = 14400;
        minDeploy = _config.minDeploy;
        minProfit = _config.minProfit;

        // PERP
        perpVault = IVault(_config.perpVault);
        clearingHouse = IClearingHouse(perpVault.getClearingHouse());
        orderBook = IOrderBook(clearingHouse.getOrderBook());
        marketRegistery = IMarketRegistry(_config.marketRegistery);
        baseToken = IBaseToken(_config.baseToken);
        tickRangeMultiplier = _config.tickRangeMultiplier;
        twapTime = _config.twapTime;
        debtMultiple = _config.debtMultiple;

        approveContracts();
    }

    function name() external view override returns (string memory) {
        return "StrategyHedgedPerp";
    }

    // reserves
    function balanceOfWant() public view returns (uint256) {
        return (want.balanceOf(address(this)));
    }

    // Total liquidity in AMM
    function getTotalLiquidity() public view returns (uint256 _liquidity) {
        OpenOrder.Info memory info = orderBook.getOpenOrder(
            address(this),
            address(short),
            lowerTick,
            upperTick
        );
        return uint256(info.liquidity);
    }

    function getBaseTokenMarkTwapPrice() public view returns (uint256) {
        IExchange exchange = IExchange(perpVault.getExchange());
        IClearingHouseConfig config = IClearingHouseConfig(
            perpVault.getClearingHouseConfig()
        );

        uint160 sqrtMarkTwapX96 = exchange.getSqrtMarkTwapX96(
            address(baseToken),
            config.getTwapInterval()
        );
        uint256 markPriceX96 = PerpMath.formatSqrtPriceX96ToPriceX96(
            sqrtMarkTwapX96
        );

        return PerpMath.formatX96ToX10_18(markPriceX96);
    }

    function getBaseTokenSpotPrice() public view returns (uint256) {
        IExchange exchange = IExchange(perpVault.getExchange());
        IClearingHouseConfig config = IClearingHouseConfig(
            perpVault.getClearingHouseConfig()
        );

        uint160 sqrtMarkTwapX96 = exchange.getSqrtMarkTwapX96(
            address(baseToken),
            0
        );
        uint256 markPriceX96 = PerpMath.formatSqrtPriceX96ToPriceX96(
            sqrtMarkTwapX96
        );

        return PerpMath.formatX96ToX10_18(markPriceX96);
    }

    // Get short Mark Price (used for lending market) which is derived from Uniswap TWAP
    function getBaseTokenMarkTwapTick() public view returns (int24) {
        IExchange exchange = IExchange(perpVault.getExchange());
        IClearingHouseConfig config = IClearingHouseConfig(
            perpVault.getClearingHouseConfig()
        );

        uint160 sqrtMarkTwapX96 = exchange.getSqrtMarkTwapX96(
            address(baseToken),
            config.getTwapInterval()
        );
        uint256 markPriceX96 = PerpMath.formatSqrtPriceX96ToPriceX96(
            sqrtMarkTwapX96
        );
        return TickMath.getTickAtSqrtRatio(sqrtMarkTwapX96);
    }

    // calculate total value of vault assets
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceDeployed());
    }

    // calculate total value of vault assets
    function balanceDeployed() public view returns (uint256) {
        return uint256(perpVault.getAccountValue(address(this)));
    }
    // calculate total value of short deployed
    function shortDeployed() public view returns (uint256 _shortAmount) {
            //uint256 sqrtMarkPriceX96 = PerpMath.getSqrtRatioAtTick(getBaseTokenMarkTwapTick());
            return LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(getBaseTokenMarkTwapTick()) > TickMath.getSqrtRatioAtTick(lowerTick) ? TickMath.getSqrtRatioAtTick(getBaseTokenMarkTwapTick()) : TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            uint128(getTotalLiquidity())
        );
    }

    // calculate total value of want deployed
    function wantDeployed() public view returns (uint256 _shortAmount) {
            return LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            uint128(getTotalLiquidity())
        );
    }

    // debt ratio - used to trigger rebalancing of debt
    function calcDebtRatio() public view returns (uint256) {
        // uint256 shortAmount = orderBook.getTotalOrderDebt(
        //     address(this),
        //     address(short),
        //     true
        // );
        uint256 shortAmount = shortDeployed();

        if (shortAmount == 0) {
            return 0;
        }
        // uint256 longAmount = orderBook.getTotalOrderDebt(
        //     address(this),
        //     address(short),
        //     false
        // );
        shortAmount = shortAmount.mul(getBaseTokenSpotPrice()).div(
            (uint256(10)**uint256(18))
        );
        uint256 ratio = _getTotalDebt()
            .mul(debtMultiple)
            .div(uint256(20000))
            .mul(uint256(10)**uint256(18).sub(wantDecimals))
            .mul(BASIS_PRECISION)
            .div(shortAmount);
        return ratio;
    }

    // calculate debt / collateral - used to trigger re-balancing of debt & collateral
    function calcCollateral() public view returns (uint256) {
        return
            perpVault.getFreeCollateral(address(this)).mul(BASIS_PRECISION).div(
                _getTotalDebt()
            );
    }

    // View pending fees (not optimism) in USD terms
    function pendingRewards() public view returns (uint256) {
        return
            orderBook.getPendingFee(
                address(this),
                address(short),
                lowerTick,
                upperTick
            );
    }

    function _getTotalDebt() internal view returns (uint256) {
        return vault.strategies(address(this)).totalDebt;
    }

    function setSlippageConfig(uint256 _slippageAdj) external onlyAuthorized {
        slippageAdj = _slippageAdj;
    }

    function setInsurance(address _insurance) external onlyAuthorized {
        require(address(insurance) == address(0));
        require(address(_insurance) != address(0));
        insurance = IStrategyInsurance(_insurance);
    }

    function setPerpVault(address _vault) external onlyAuthorized {
        perpVault = IVault(_vault);
    }

    /**
     * function to set debt thresholds before rebalancing
     *
     * @param _lower lower debt ratio
     * @param _upper upper debt ratio
     */

    function setDebtThresholds(uint256 _lower, uint256 _upper)
        external
        onlyAuthorized
    {
        require(_lower <= BASIS_PRECISION);
        require(_lower < _upper);
        //require(_debtMultiple <= BASIS_PRECISION.mul(10));
        require(_lower < _upper);
        debtUpper = _upper;
        debtLower = _lower;
        //debtMultiple = _debtMultiple;
    }

    function setCollateralThresholds(
        uint256 _lower,
        uint256 _debtMultiple,
        uint256 _upper,
        uint256 _limit
    ) external onlyAuthorized {
        require(_limit <= BASIS_PRECISION);
        collatLimit = _limit;
        require(collatLimit > _upper);
        require(_upper > _lower);
        collatUpper = _upper;
        debtMultiple = _debtMultiple;
        collatLower = _lower;
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalAssets = estimatedTotalAssets();
        uint256 totalDebt = _getTotalDebt();
        if (totalAssets > totalDebt) {
            _profit = totalAssets.sub(totalDebt);
            (uint256 amountFreed, ) = _withdraw(_debtOutstanding.add(_profit));
            if (_debtOutstanding > amountFreed) {
                _debtPayment = amountFreed;
                _profit = 0;
            } else {
                _debtPayment = _debtOutstanding;
                _profit = amountFreed.sub(_debtOutstanding);
            }
        } else {
            _withdraw(_debtOutstanding);
            _debtPayment = balanceOfWant();
            _loss = totalDebt.sub(totalAssets);
        }

        if (pendingRewards() > minProfit) {
            _profit += _harvestInternal();
        }

        // Check if we're net loss or net profit
        if (_loss >= _profit) {
            _loss = _loss.sub(_profit);
            _profit = 0;
            _loss = _loss.sub(insurance.reportLoss(totalDebt, _loss));
        } else {
            _profit = _profit.sub(_loss);
            _loss = 0;
            (uint256 insurancePayment, uint256 compensation) = insurance
                .reportProfit(totalDebt, _profit);
            _profit = _profit.sub(insurancePayment).add(compensation);

            // double check insurance isn't asking for too much or zero
            if (insurancePayment > 0 && insurancePayment < _profit) {
                SafeERC20.safeTransfer(
                    want,
                    address(insurance),
                    insurancePayment
                );
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _wantAvailable = balanceOfWant();
        if (_debtOutstanding >= _wantAvailable) {
            return;
        }
        uint256 toInvest = _wantAvailable.sub(_debtOutstanding);

        if (toInvest > 0) {
            _deploy(toInvest);
        }
    }

    function approveContracts() internal {
        want.safeApprove(address(perpVault), type(uint256).max);
    }

    function prepareMigration(address _newStrategy) internal override {
        liquidateAllPositionsInternal();
    }

    function migrateInsurance(address _newInsurance) external onlyGovernance {
        require(address(_newInsurance) == address(0));
        insurance.migrateInsurance(_newInsurance);
        insurance = IStrategyInsurance(_newInsurance);
    }

    function liquidatePositionAuth(uint256 _amount) external onlyAuthorized {
        (uint256 _liquidatedAmount, uint256 _loss) = liquidatePosition(_amount);
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        (_amountFreed, ) = liquidateAllPositionsInternal();
    }

    function liquidateAllPositionsInternal()
        internal
        returns (uint256 _amountFreed, uint256 _loss)
    {
        liquidateAllToLend();
        _removeCollateral(perpVault.getFreeCollateral(address(this)));
        _amountFreed = balanceOfWant();
    }

    /// re-balances vault holding of short token vs LP to within target collateral range
    function rebalanceDebt() external onlyKeepers {
        uint256 debtRatio = calcDebtRatio();
        require(debtRatio < debtLower || debtRatio > debtUpper);
        _rebalanceDebtInternal();
    }

    /// re-balances vault holding of short token vs LP to within target collateral range
    function rebalanceCollateral() external onlyKeepers {
        uint256 collatRatio = calcCollateral();
        require(collatRatio < collatLower || collatRatio > collatUpper);
        _rebalanceCollateralInternal();
    }

    function exec(address _target, bytes memory _data) external onlyAuthorized {
        PerpLib.exec(_target, _data);
    }

    function liquidateAllToLend()
        internal
        returns (IClearingHouse.RemoveLiquidityResponse memory _resp)
    {
        require(getTotalLiquidity() > 0, "RL_LIQ");
        _collectPendingFees();
        IClearingHouse.RemoveLiquidityParams memory params = IClearingHouse
            .RemoveLiquidityParams({
                baseToken: address(short),
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidity: uint128(getTotalLiquidity()),
                minBase: 0,
                minQuote: 0,
                deadline: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            });
        _resp = clearingHouse.removeLiquidity(params);
        //_closePosition(); //TODO: Bring back later
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 balanceWant = balanceOfWant();
        uint256 totalAssets = estimatedTotalAssets();
        // if estimatedTotalAssets is less than params.debtRatio it means there's
        // been a loss (ignores pending harvests). This type of loss is calculated
        // proportionally
        // This stops a run-on-the-bank if there's IL between harvests.
        uint256 newAmount = _amountNeeded;
        uint256 totalDebt = _getTotalDebt();
        if (totalDebt > totalAssets) {
            uint256 ratio = totalAssets.mul(STD_PRECISION).div(totalDebt);
            newAmount = _amountNeeded.mul(ratio).div(STD_PRECISION);
            _loss = _amountNeeded.sub(newAmount);
        }
        // Liquidate the amount needed
        (, uint256 _slippage) = _withdraw(newAmount);
        _loss = _loss.add(_slippage);
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        _liquidatedAmount = balanceOfWant();
        if (_liquidatedAmount.add(_loss) > _amountNeeded) {
            _liquidatedAmount = _amountNeeded.sub(_loss);
        } else {
            _loss = _amountNeeded.sub(_liquidatedAmount);
        }
    }

    /// called by keeper to harvest rewards and either repay debt
    uint256 constant DUST_LIQ = 100;

    function _harvestInternal() internal returns (uint256 _wantHarvested) {
        //TODO PERP how does the farming work? Do we need to harvest and auto-compound? Is it all automatic?
        if (getTotalLiquidity() < DUST_LIQ) {
            return 0;
        }
        IClearingHouse.RemoveLiquidityResponse
            memory response = _collectPendingFees();
        return response.fee;
    }

    // deploy assets according to vault strategy
    function _deploy(uint256 _amount) internal {
        // TODO: Add check for collateral cap here
        if (_amount < minDeploy) {
            return;
        }

        //Deposit into perp
        _addCollateral(_amount);
        _deployFromLend(_amount);
        //TODO PERP: make sure that we have USDC for fees
    }

    function _determineTicks() internal {
        IUniswapV3Pool pool = IUniswapV3Pool(
            marketRegistery.getPool(address(short))
        );

        (lowerTick, upperTick) = PerpLib.determineTicks(
            pool,
            twapTime,
            tickRangeMultiplier
        );
    }

    function _addLiquidityToShortMarket(uint256 _amount)
        internal
        returns (IClearingHouse.AddLiquidityResponse memory _resp)
    {
        uint256 amountInSTD = _amount.mul(uint256(10)**(18 - wantDecimals));
        uint256 twapMarkPrice = getBaseTokenMarkTwapPrice();
        uint256 amountShortNeeded = amountInSTD
            .mul(STD_PRECISION)
            .div(twapMarkPrice)
            .div(uint256(2));
        IClearingHouse.AddLiquidityParams memory params = IClearingHouse
            .AddLiquidityParams({
                baseToken: address(short),
                base: amountShortNeeded,
                quote: amountInSTD.div(2),
                lowerTick: lowerTick,
                upperTick: upperTick,
                minBase: 0, //amountShortNeeded.mul(slippageAdj).div(
                //    BASIS_PRECISION
                //),
                minQuote: 0, //(amountInSTD.div(2)).mul(slippageAdj).div(
                //    BASIS_PRECISION
                //),
                useTakerBalance: bool(false),
                deadline: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            });
        _resp = clearingHouse.addLiquidity(params);
    }

    function _removeCollateral(uint256 _amount) internal {
        // Withdraw from perp
        perpVault.withdraw(address(want), _amount);
    }

    function _addCollateral(uint256 _amount) internal {
        // Deposit into perp
        perpVault.deposit(address(want), _amount);
    }

    function _collectPendingFees()
        public
        returns (IClearingHouse.RemoveLiquidityResponse memory _resp)
    {
        IClearingHouse.RemoveLiquidityParams memory params = IClearingHouse
            .RemoveLiquidityParams({
                baseToken: address(short),
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidity: 0,
                minBase: 0,
                minQuote: 0,
                deadline: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            });
        try clearingHouse.removeLiquidity(params) returns (IClearingHouse.RemoveLiquidityResponse memory _resp) {
            //_resp = resp;
        } catch Error(string memory reason) {
            emit Log(reason,2);
        }
        //_resp = clearingHouse.removeLiquidity(params);
    }
    event Log(string log, uint256 number);
    function _closePosition() public returns (uint256 _base, uint256 _quote) {
        IClearingHouse.ClosePositionParams memory params = IClearingHouse
            .ClosePositionParams({
                baseToken: address(short),
                sqrtPriceLimitX96: 0,
                oppositeAmountBound: 0,
                deadline: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                referralCode: bytes32(bytes("ROBO"))
            });
        try clearingHouse.closePosition(params) returns (uint256 base, uint256 quote){
            //emit Debug(base, 808);
            //emit Debug(quote, 809);
            _base = base;
            _quote = quote;

        } catch Error(string memory reason) {
            emit Log(reason,1);
        }
        //(_base, _quote) = clearingHouse.closePosition(params);
    }

    function _deployFromLend(uint256 _amount) internal {
        if (getTotalLiquidity() > 0) {
            liquidateAllToLend();
        }
        _determineTicks();
        uint256 leverageAmount = _amount.mul(debtMultiple).div(BASIS_PRECISION);
        _addLiquidityToShortMarket(leverageAmount);
    }

    function _rebalanceDebtInternal() internal {
        uint256 debtRatio = calcDebtRatio();
        emit DebtRebalance(debtRatio, balanceDeployed(), 0);
        // Liquidate all the lend, leaving none in debt or as short
        if (getTotalLiquidity() > 0) {
            liquidateAllToLend();
            _closePosition();
        }
        _deployFromLend(estimatedTotalAssets());
    }

    function _rebalanceCollateralInternal() internal {
        uint256 collatRatio = calcCollateral();

        emit CollatRebalance(collatRatio, balanceDeployed());
        // Liquidate all the lend, leaving none in debt or as short
        if (getTotalLiquidity() > 0) {
            liquidateAllToLend();
            _closePosition();
        }
        _deployFromLend(estimatedTotalAssets());
    }

    /**
     * function to remove funds from strategy when users withdraws funds in excess of reserves
     *
     * withdraw takes the following steps:
     * 1. Removes _amountNeeded worth of LP from the farms and pool
     * 2. Uses the short removed to repay debt (Swaps short or base for large withdrawals)
     * 3. Redeems the
     * @param _amountNeeded `want` amount to liquidate
     */
    function _withdraw(uint256 _amountNeeded)
        internal
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 balanceWant = balanceOfWant();
        uint256 deployed = balanceDeployed();
        if (_amountNeeded <= balanceWant) {
            return (_amountNeeded, 0);
        }
        // stratPercent: Percentage of the deployed capital we want to liquidate.
        uint256 stratPercent = _amountNeeded
            .sub(balanceWant)
            .mul(BASIS_PRECISION)
            .div(deployed);
        emit Debug(stratPercent, 601);
        if (stratPercent > 9500) {
            // If this happened, we just undeploy the lot
            // and it'll be redeployed during the next harvest.
            (, _loss) = liquidateAllPositionsInternal();
            _liquidatedAmount = balanceOfWant().sub(balanceWant);
        } else {
            liquidateAllToLend();
            _amountNeeded = _amountNeeded;
            _removeCollateral(_amountNeeded);
            if (_getTotalDebt() > _amountNeeded) {
                _addLiquidityToShortMarket(deployed.sub(_amountNeeded));
            }
            return (balanceOfWant().sub(balanceWant), 0);
        }
    }

    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // This is not currently used by the strategies and is
        // being removed to reduce the size of the contract
        return 0;
    }

    /**
     * @notice
     *  Intentionally not implmenting this. The justification being:
     *   1. It doesn't actually add any additional security because gov
     *      has the powers to do the same thing with addStrategy already
     *   2. Being able to sweep tokens from a strategy could be helpful
     *      incase of an unexpected catastropic failure.
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}
}
