-include .env

.PHONY: all test deploy

build :; forge build

test :; forge test

install :; forge install cyfrin/foundry-devops@v0.2.2 --commit && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --commit && forge install foundry-rs/forge-std@v1.8.2 --commit && forge install transmissions11/solmate@v6 --commit

deploy-sepolia :
	@forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(SEPOLIA_RPC_URL) --account dev --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv