import brownie
from brownie import interface, accounts
import pytest
import time 

def strategySharePrice(strategy, vault):
    return strategy.estimatedTotalAssets() / vault.strategies(strategy)['totalDebt']

def steal(stealPercent, strategy, token, chain, gov, user):
    steal = round(strategy.estimatedTotalAssets() * stealPercent)
    strategy.liquidatePositionAuth(steal, {'from': gov})
    token.transfer(user, strategy.balanceOfWant(), {"from": accounts.at(strategy, True)})
    chain.sleep(1)
    chain.mine(1)

def test_change_debt_lossy(
    chain, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    vault.updateStrategyDebtRatio(strategy.address, 100_00, {"from": gov})
    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    

    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)

    # Steal from the strategy
    steal = round(strategy.estimatedTotalAssets() * 0.01)
    strategy.liquidatePositionAuth(steal, {'from': gov})
    token.transfer(user, strategy.balanceOfWant(), {"from": accounts.at(strategy, True)})
    vault.updateStrategyDebtRatio(strategy.address, 50_00, {"from": gov})

    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    
    assert 1==2
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-2) == int(amount * 0.98 / 2) 

    vault.updateStrategyDebtRatio(strategy.address, 0, {"from": gov})

    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    

    strategy.harvest()
    assert strategy.estimatedTotalAssets() < 10 ** (token.decimals() - 3) # near zero


def test_profitable_harvest(
    chain, accounts, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf, whale
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount
    before_pps = vault.pricePerShare()

    # Use a whale of the harvest token to send
    sendAmount = round(vault.totalAssets()* 0.05)
    print('Send amount: {0}'.format(sendAmount))
    print('harvestWhale balance: {0}'.format(token.balanceOf(whale)))
    token.transfer(strategy, sendAmount, {'from': whale})

    # Harvest 2: Realize profit
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest()
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit = token.balanceOf(vault.address)  # Profits go to vault

    assert strategy.estimatedTotalAssets() + profit > amount
    assert vault.pricePerShare() > before_pps

def test_set_debt_thresholds(strategy, gov, user, vault, token, amount, chain):
    # Only the governance account can set the debt thresholds
    with brownie.reverts(""):
        strategy.setDebtThresholds(9900, 101000, {"from": user})
    
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount
    
    # harvest
    chain.sleep(1)
    chain.mine(1)

    # The debt thresholds can be updated by the governance account
    strategy.setDebtThresholds(9900, 101000, {"from": gov})
    strategy.harvest()
    assert strategy.debtUpper() == 101000
    assert strategy.debtLower() == 9900
    assert strategy.debtMultiple() == 10000
    assert pytest.approx(strategy.calcDebtRatio(), rel=1e-2) == 10000

def test_set_collateral_thresholds(strategy, gov, user, vault, token, amount, chain):
    # Only the governance account can set the debt thresholds
    with brownie.reverts(""):
        strategy.setCollateralThresholds(8900, 10000, 9100, 10000, {"from": user})
    
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount
    
    # harvest
    chain.sleep(1)
    chain.mine(1)

    # The debt thresholds can be updated by the governance account
    strategy.setCollateralThresholds(8900, 10000, 9100, 10000, {"from": gov})
    strategy.setDebtThresholds(9900, 101000, {"from": gov})
    strategy.harvest()
    assert strategy.collatLower() == 8900
    assert strategy.collatUpper() == 9100
    assert strategy.debtMultiple() == 10000
    assert pytest.approx(((100000 - strategy.debtMultiple())/10), rel=1e-2) == strategy.calcCollateral()
    assert pytest.approx(strategy.calcDebtRatio(), rel=1e-2) == 10000

    # The debt thresholds can be updated by the governance account
    strategy.setCollateralThresholds(5900, 40000, 6100, 10000, {"from": gov})
    strategy.setDebtThresholds(9900, 101000, {"from": gov})
    strategy.rebalanceCollateral()
    assert strategy.collatLower() == 5900
    assert strategy.collatUpper() == 6100
    assert strategy.debtMultiple() == 40000
    assert pytest.approx(((100000 - strategy.debtMultiple())/10), rel=1e-2) == strategy.calcCollateral()
    assert pytest.approx(strategy.calcDebtRatio(), rel=1e-2) == 10000

        # The debt thresholds can be updated by the governance account
    strategy.setCollateralThresholds(7900, 20000, 8100, 10000, {"from": gov})
    strategy.setDebtThresholds(9900, 101000, {"from": gov})
    strategy.rebalanceCollateral()
    assert strategy.collatLower() == 7900
    assert strategy.collatUpper() == 8100
    assert strategy.debtMultiple() == 20000
    assert pytest.approx(((100000 - strategy.debtMultiple())/10), rel=1e-2) == strategy.calcCollateral()
    assert pytest.approx(strategy.calcDebtRatio(), rel=1e-2) == 10000

def test_operation(
    chain, accounts, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf, whale, keeper
):
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    #assert 1==2
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount
    
    # harvest
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest()
    strat = strategy
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount
    # # make tiny swap to avoid issue where dif
    # swapPct = 1 / 1000
    # offSetDebtRatioHigh(strategy, lp_token, token, Contract, swapPct, router, whale) 
    # # check debt ratio
    debtRatio = strategy.calcDebtRatio()
    # collatRatio = strategy.calcCollateral()
    print('debtRatio:   {0}'.format(debtRatio))
    # print('collatRatio: {0}'.format(collatRatio))
    assert pytest.approx((10000*10000)/strategy.debtMultiple(), rel=1e-2) == debtRatio #rel=1e-3
    # assert pytest.approx(6000, rel=1e-2) == collatRatio
    # This part should have been done by harvest... weird that lowerTick and upperTick arent set at this point
    # strategy._determineTicks({'from': keeper});

    # withdrawal
    vault.withdraw(amount, user, 500, {'from' : user}) 
    assert (
        pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before
    )

def test_sweep(gov, vault, strategy, token, user, amount, conf):
    # Strategy want token doesn't work
    token.transfer(strategy, amount, {"from": user})
    assert token.address == strategy.want()
    assert token.balanceOf(strategy) > 0
    with brownie.reverts("!want"):
        strategy.sweep(token, {"from": gov})

    # Vault share token doesn't work
    with brownie.reverts("!shares"):
        strategy.sweep(vault.address, {"from": gov})



def test_triggers(
    chain, gov, vault, strategy, token, amount, user, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()

    strategy.harvestTrigger(0)
    strategy.tendTrigger(0)



def test_lossy_withdrawal(
    chain, gov, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    vault.updateStrategyDebtRatio(strategy.address, 100_00, {"from": gov})
    chain.sleep(1)
    chain.mine(1)

    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # Steal from the strategy
    stealPercent = 0.01
    chain.sleep(1)
    chain.mine(1)
    steal(stealPercent, strategy, token, chain, gov, user)

    chain.mine(1)
    balBefore = token.balanceOf(user)
    assert 1==2
    vault.withdraw(amount, user, 150, {'from' : user}) 
    balAfter = token.balanceOf(user)
    assert pytest.approx(balAfter - balBefore, rel = 2e-3) == int(amount * .99)


def test_lossy_withdrawal_partial(
    chain, gov, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    vault.updateStrategyDebtRatio(strategy.address, 100_00, {"from": gov})

    chain.sleep(1)
    chain.mine(1)

    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount


    # Steal from the strategy
    stealPercent = 0.005
    chain.sleep(1)
    chain.mine(1)
    steal(stealPercent, strategy, token, chain, gov, user)

    balBefore = token.balanceOf(user)
    ssp_before = strategySharePrice(strategy, vault)

    #give RPC a little break to stop it spzzing out 
    time.sleep(5)

    half = int(amount / 2)
    vault.withdraw(half, user, 100, {'from' : user}) 
    balAfter = token.balanceOf(user)
    assert pytest.approx(balAfter - balBefore, rel = 2e-3) == (half * (1-stealPercent)) 

    # Check the strategy share price wasn't negatively effected
    ssp_after = strategySharePrice(strategy, vault)
    assert pytest.approx(ssp_before, rel = 2e-5) == ssp_after


def test_lossy_withdrawal_tiny(
    chain, gov, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})


    vault.updateStrategyDebtRatio(strategy.address, 100_00, {"from": gov})
    chain.sleep(1)
    chain.mine(1)

    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    chain.sleep(1)
    chain.mine(1)
    # Steal from the strategy
    stealPercent = 0.005
    steal(stealPercent, strategy, token, chain, gov, user)
    
    balBefore = token.balanceOf(user)
    ssp_before = strategySharePrice(strategy, vault)

    #give RPC a little break to stop it spzzing out 
    time.sleep(5)

    tiny = int(amount * 0.001)
    vault.withdraw(tiny, user, 100, {'from' : user}) 
    balAfter = token.balanceOf(user)
    assert pytest.approx(balAfter - balBefore, rel = 2e-3) == (tiny * (1-stealPercent)) 

    # Check the strategy share price wasn't negatively effected
    ssp_after = strategySharePrice(strategy, vault)
    assert pytest.approx(ssp_before, rel = 2e-5) == ssp_after


def test_lossy_withdrawal_99pc(
    chain, gov, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    vault.updateStrategyDebtRatio(strategy.address, 100_00, {"from": gov})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    chain.sleep(1)
    chain.mine(1)
    # Steal from the strategy
    stealPercent = 0.005
    steal(stealPercent, strategy, token, chain, gov, user)

    balBefore = token.balanceOf(user)
    ssp_before = strategySharePrice(strategy, vault)

    #give RPC a little break to stop it spzzing out 
    time.sleep(5)

    tiny = int(amount * 0.99)
    vault.withdraw(tiny, user, 100, {'from' : user}) 
    balAfter = token.balanceOf(user)
    assert pytest.approx(balAfter - balBefore, rel = 2e-3) == (tiny * (1-stealPercent)) 

    # Check the strategy share price wasn't negatively effected
    ssp_after = strategySharePrice(strategy, vault)
    assert pytest.approx(ssp_before, rel = 2e-5) == ssp_after


def test_lossy_withdrawal_95pc(
    chain, gov, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf, deployed_vault
):

    chain.sleep(1)
    chain.mine(1)
    # Steal from the strategy
    stealPercent = 0.005
    steal(stealPercent, strategy, token, chain, gov, user)

    balBefore = token.balanceOf(user)
    ssp_before = strategySharePrice(strategy, vault)

    #give RPC a little break to stop it spzzing out 
    time.sleep(5)
    chain.sleep(1)
    chain.mine(1)

    tiny = int(amount * 0.95)
    vault.withdraw(tiny, user, 100, {'from' : user}) 
    balAfter = token.balanceOf(user)
    assert pytest.approx(balAfter - balBefore, rel = 2e-3) == (tiny * (1-stealPercent)) 

    # Check the strategy share price wasn't negatively effected
    ssp_after = strategySharePrice(strategy, vault)
    assert pytest.approx(ssp_before, rel = 2e-5) == ssp_after

def test_set_slippage_config(strategy, gov, user):
    # Only the governance account can set the slippage config
    with brownie.reverts(""):
        strategy.setSlippageConfig(500, {"from": user})

    # The slippage config can be updated by the governance account
    strategy.setSlippageConfig(500, {"from": gov})
    assert strategy.slippageAdj() == 500
    
def test_set_perp_vault(strategy, gov, user):
    # Only the governance account can set the slippage config
    with brownie.reverts(""):
        strategy.setPerpVault(user, {"from": user})

    # The slippage config can be updated by the governance account
    strategy.setPerpVault(user, {"from": gov})
    assert strategy.perpVault() == user


# def test_set_insurance(strategy, gov, user):
#     # Only the governance account can set the insurance contract
#     with brownie.reverts(""):
#         strategy.setInsurance(user, {"from": gov})

#     # The insurance contract can be set by the governance account
#     strategy.setInsurance(user, {"from": gov})
#     assert strategy.insurance() == user

def test_set_perp_vault(strategy, gov, user):
    # Only the governance account can set the Perp vault contract
    with brownie.reverts(""):
        strategy.setPerpVault(user, {"from": user})

    # The Perp vault contract can be set by the governance account
    strategy.setPerpVault(user, {"from": gov})
    assert strategy.perpVault() == user

def test_emergency_exit(
    chain, accounts, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # set emergency and exit
    strategy.setEmergencyExit()
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest()
    assert strategy.estimatedTotalAssets() < 10 ** (token.decimals() - 3) # near zero
    assert pytest.approx(token.balanceOf(vault), rel=RELATIVE_APPROX) == amount

def test_change_debt(
    chain, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 50_00, {"from": gov})

    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    strategy.harvest()
    half = int(amount / 2)
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == half

    vault.updateStrategyDebtRatio(strategy.address, 100_00, {"from": gov})
    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    vault.updateStrategyDebtRatio(strategy.address, 50_00, {"from": gov})
    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == half

    vault.updateStrategyDebtRatio(strategy.address, 0, {"from": gov})
    chain.sleep(1)
    chain.mine(1)
    time.sleep(1)
    
    strategy.harvest()
    assert strategy.estimatedTotalAssets() < 10 ** (token.decimals() - 3) # near zero
