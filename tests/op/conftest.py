import pytest
from brownie import config
from brownie import interface, StrategyInsurance, project, accounts

CONFIG = {
    "USDC": {
        "token": "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
        "whale": "0x625e7708f30ca75bfd92586e17077590c60eb4cd",
        "vault": "0x49d743E645C90ef4c6D5134533c1e62D08867b14",
    },
}

@pytest.fixture
def strategy_contract():
    yield  project.PerpStrategyProject.WETHPERP

@pytest.fixture
def perplib_contract():
    yield  project.PerpStrategyProject.PerpLib

@pytest.fixture
def conf(strategy_contract):
    yield CONFIG[strategy_contract._name]

@pytest.fixture
def gov(accounts):
    #yield accounts.at("0x7601630eC802952ba1ED2B6e4db16F699A0a5A87", force=True)
    yield accounts[1]

@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]



@pytest.fixture
def token_name():
    yield "USDC"
    # yield "WETH"


@pytest.fixture
def conf(token_name):
    yield CONFIG[token_name]


@pytest.fixture
def gov(accounts):
    # yield accounts.at("0x7601630eC802952ba1ED2B6e4db16F699A0a5A87", force=True)
    yield accounts[1]


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def treasury(accounts):
    yield accounts[2]


@pytest.fixture
def token(conf):
    yield interface.IERC20Extended(conf["token"])


@pytest.fixture
def whale(conf, accounts):
    yield accounts.at(conf["whale"], True)


@pytest.fixture
def amount(token, whale, user):
    amount = 10_000 * 10 ** token.decimals()
    amount = min(amount, int(0.5 * token.balanceOf(whale)))
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at(whale, force=True)
    token.transfer(user, amount, {"from": reserve})
    yield amount


# @pytest.fixture
# def vault(conf):
#     vault = interface.IVault(conf["vault"])
#     yield vault

@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    assert vault.token() == token.address
    yield vault

@pytest.fixture
def perp_lib(gov, perplib_contract):
    lib = perplib_contract.deploy({'from': gov});
    yield lib

@pytest.fixture
def strategy(vault, gov, user, strategist, keeper,  strategy_contract, perp_lib):
    strategy = strategy_contract.deploy(vault, {'from': gov})
    insurance = strategist.deploy(StrategyInsurance, strategy)
    strategy.setKeeper(keeper)
    strategy.setInsurance(insurance, {'from': gov})
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


# @pytest.fixture
# def brownie_template(gov, treasury):
#     brownie_template = gov.deploy(BrownieTemplate, treasury)
#     yield brownie_template


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5
