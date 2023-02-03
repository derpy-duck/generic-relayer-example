import { Hub__factory } from "../../ts-test/src/ethers-contracts/factories/Hub__factory"
import { Spoke__factory } from "../../ts-test/src/ethers-contracts/factories/Spoke__factory"
import { ChainId } from "@certusone/wormhole-sdk"

import {
  ChainInfo,
  Deployment,
  getSigner,
} from "./env"
import { ethers } from "ethers"

export async function deployHub(chain: ChainInfo): Promise<Deployment> {
  console.log("deploy Hub on chain " + chain.chainId)

  let signer = getSigner(chain.chainId)
  const contractInterface = Hub__factory.createInterface()
  const bytecode = Hub__factory.bytecode
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy(
    chain.wormholeAddress,
    chain.coreRelayerAddress
  )
  return await contract.deployed().then((result) => {
    console.log(`Successfully deployed Hub (chain ${chain.chainId}) at ` + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}

export async function deploySpoke(chain: ChainInfo, hubAddress: string, hubChain: ChainId): Promise<Deployment> {
  console.log("deploy Spoke on chain " + chain.chainId)

  let signer = getSigner(chain.chainId)
  const contractInterface = Spoke__factory.createInterface()
  const bytecode = Spoke__factory.bytecode
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy(
    chain.wormholeAddress,
    chain.coreRelayerAddress,
    hubAddress,
    hubChain
  )
  return await contract.deployed().then((result) => {
    console.log(`Successfully deployed Spoke (chain ${chain.chainId}) at ` + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}

