import brownie
from brownie import interface, accounts
import pytest
import time 

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

def test_set_slippage_config(strategy, gov, user):
    # Only the governance account can set the slippage config
    with brownie.reverts(""):
        strategy.setSlippageConfig(500, {"from": user})

    # The slippage config can be updated by the governance account
    strategy.setSlippageConfig(500, {"from": gov})
    assert strategy.slippageAdj() == 500


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
