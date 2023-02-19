import brownie
from brownie import interface, accounts
import pytest


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


def test_set_debt_thresholds(strategy, gov, user):
    # Only the governance account can set the debt thresholds
    with brownie.reverts(""):
        strategy.setDebtThresholds(9900, 101000, 10000, {"from": user})

    # The debt thresholds can be updated by the governance account
    strategy.setDebtThresholds(9900, 101000, 10000, {"from": gov})
    assert strategy.debtUpper() == 101000
    assert strategy.debtLower() == 9900
    assert strategy.debtMultiple() == 10000