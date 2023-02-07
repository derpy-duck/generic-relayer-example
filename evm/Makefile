include testing.env

.PHONY: dependencies unit-test forge-test integration-test clean all

all: build

.PHONY: clean
clean:
	rm -rf anvil.log node_modules lib out

.PHONY: dependencies
dependencies: node_modules lib/forge-std update-submodules

node_modules:
	yarn

lib/forge-std:
	forge install foundry-rs/forge-std --no-git --no-commit

build: dependencies
	forge build
	yarn build-types

ts-relayer-sdk:
	git clone --depth 1 --branch ts-additions --single-branch https://github.com/wormhole-foundation/trustless-generic-relayer.git ../submodules/trustless-generic-relayer

update-submodules:
	git submodule update --init --recursive

.PHONY: unit-test
unit-test: forge-test

.PHONY: forge-test-short
forge-test-fast: dependencies
	FOUNDRY_FUZZ_RUNS=1 forge test --fork-url ${TESTING_FUJI_FORK_RPC} --match-test testFullFlow1Msg

.PHONY: forge-test
forge-test: dependencies
	FOUNDRY_FUZZ_RUNS=1 forge test --fork-url ${TESTING_FUJI_FORK_RPC} 


.PHONY: forge-test-logs
forge-test-logs: dependencies
	FOUNDRY_FUZZ_RUNS=1 forge test --fork-url ${TESTING_FUJI_FORK_RPC} -vvvvv --match-test testFullFlow1Msg

.PHONY: forge-test-verbose
forge-test-verbose: dependencies
	FOUNDRY_FUZZ_RUNS=1 forge test --fork-url ${TESTING_FUJI_FORK_RPC} -vvv --match-test testFullFlow1Msg

.PHONY: forge-test-long
forge-test-long: dependencies
	forge test --fork-url ${TESTING_FUJI_FORK_RPC} 

