import brownie
from brownie import interface, accounts
import pytest


def test_operation(
    chain, accounts, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, conf, whale
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
    assert 1==2
    # # make tiny swap to avoid issue where dif
    # swapPct = 1 / 1000
    # offSetDebtRatioHigh(strategy, lp_token, token, Contract, swapPct, router, whale) 
    # # check debt ratio
    debtRatio = strategy.calcDebtRatio()
    # collatRatio = strategy.calcCollateral()
    print('debtRatio:   {0}'.format(debtRatio))
    # print('collatRatio: {0}'.format(collatRatio))
    assert pytest.approx(10000, rel=1e-2) == debtRatio #rel=1e-3
    # assert pytest.approx(6000, rel=1e-2) == collatRatio
    # This part should have been done by harvest... weird that lowerTick and upperTick arent set at this point
    strategy._determineTicks() 

    # withdrawal
    vault.withdraw(amount, user, 500, {'from' : user}) 
    assert (
        pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before
    )
