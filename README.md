# xChat: Example Wormhole Generic Relayer Integration in EVM

xChat uses a Hub and Spoke model to create a group chat between members on different chains. 

Specifically, a Hub contract is deployed onto one chain, and Spoke contracts are deployed onto all desired chains. 

Users can send messages through any spoke contract. The message is passed to the Hub chain using Wormhole, and relayed using Wormhole's default generic relayer. 


## Prerequisites

Install [Foundry tools](https://book.getfoundry.sh/getting-started/installation), which include `forge`, `anvil` and `cast` CLI tools.

Navigate to the 'evm' folder for all the below steps:
```
cd evm
``` 

## Build

Run the following commands to install necessary dependencies and to build the smart contracts:

```
make dependencies
make build
```

## Test Suite

Run the Solidity based unit tests:

```
make forge-test
```
(takes around 2-3 minutes)

For a quicker test, try
```
make forge-test-fast
```

## Interface with TestNet deployed contracts

First set an environment variable WALLET_KEY to be your wallet's private key. Then,
```
cd ts-deploy-scripts
ts-node testContracts.ts 
```
This should list all the valid methods you can use. For example, you can:
```
ts-node testContracts deploy hub 6
ts-node testContracts deploy spoke 6
ts-node testContracts deploy spoke 4
ts-node testContracts deploy spoke 14
ts-node testContracts spoke 6 register
ts-node testContracts spoke 4 register
ts-node testContracts spoke 14 register
ts-node testContracts.ts spoke 4 sendMessage "This is a message from chain 4!"
ts-node testContracts.ts spoke 6 getMessages 
```