import { ChainId } from "@certusone/wormhole-sdk"
import { ethers, Signer } from "ethers"
import fs from "fs"
import {
  Hub,
  Spoke,
  Hub__factory,
  Spoke__factory
} from "../../ts-test/src/ethers-contracts"

export type ChainInfo = {
  evmNetworkId: number
  chainId: ChainId
  rpc: string
  wormholeAddress: string
  coreRelayerAddress: string
  description: string
}

export type Deployment = {
  chainId: ChainId
  address: string
}

const DEFAULT_ENV = "testnet"

export let env = ""
let lastRunOverride: boolean | undefined

export function init(overrides: { lastRunOverride?: boolean } = {}): string {
  env = get_env_var("ENV")
  if (!env) {
    console.log("No environment was specified, using default environment files")
    env = DEFAULT_ENV
  }
  lastRunOverride = overrides?.lastRunOverride

  require("dotenv").config({
    path: `./.env${env != DEFAULT_ENV ? "." + env : ""}`,
  })
  return env
}

function get_env_var(env: string): string {
  const v = process.env[env]
  return v || ""
}

export function loadChains(): ChainInfo[] {
  const chainFile = fs.readFileSync(`./${env}/chains.json`)
  const chains = JSON.parse(chainFile.toString())
  if (!chains.chains) {
    throw Error("Failed to pull chain config file!")
  }
  return chains.chains
}

export function getChain(chain: ChainId): ChainInfo {
  const chains = loadChains()
  const output = chains.find((x) => x.chainId == chain)
  if (!output) {
    throw Error("bad chain ID")
  }

  return output
}

export function loadPrivateKey(): string {
  const privateKey = get_env_var("WALLET_KEY")
  if (!privateKey) {
    throw Error("Failed to find private key for this process!")
  }
  return privateKey
}

export function loadHub(): Deployment {
  const contractsFile = fs.readFileSync(`./config/${env}/contracts.json`)
  if (!contractsFile) {
    throw Error("Failed to find contracts file for this process!")
  }
  const contracts = JSON.parse(contractsFile.toString())
  if (contracts.useLastRun || lastRunOverride) {
    const lastRunFile = fs.readFileSync(
      `./output/${env}/deployHubAndSpokes/lastrun.json`
    )
    if (!lastRunFile) {
      throw Error("Failed to find last run file for the deploy mock integration process!")
    }
    const lastRun = JSON.parse(lastRunFile.toString())
    return lastRun.hub
  } else {
    return contracts.hub
  }
}

export function loadSpokes(): Deployment[] {
  const contractsFile = fs.readFileSync(`./config/${env}/contracts.json`)
  if (!contractsFile) {
    throw Error("Failed to find contracts file for this process!")
  }
  const contracts = JSON.parse(contractsFile.toString())
  if (contracts.useLastRun || lastRunOverride) {
    const lastRunFile = fs.readFileSync(
      `./output/${env}/deployHubAndSpokes/lastrun.json`
    )
    if (!lastRunFile) {
      throw Error("Failed to find last run file for the deploy mock integration process!")
    }
    const lastRun = JSON.parse(lastRunFile.toString())
    return lastRun.spokes
  } else {
    return contracts.spokes
  }
}

export function writeToContracts(output: any) {
  const contractsFile = fs.readFileSync(`./config/${env}/contracts.json`)
  const contracts = JSON.parse(contractsFile.toString())
  if(output.hub) {
    contracts.hub = output.hub;
  } else {
    if(output.spoke) {
      contracts.spokes = contracts.spokes.filter((s: any)=>(s.chainId !== output.spoke.chainId)).concat([output.spoke])
    }
  }
  fs.writeFileSync(`./config/${env}/contracts.json`, JSON.stringify(contracts))
}

export function writeOutputFiles(output: any, processName: string) {
  fs.mkdirSync(`./output/${env}/${processName}`, { recursive: true })
  fs.writeFileSync(
    `./output/${env}/${processName}/lastrun.json`,
    JSON.stringify(output),
    { flag: "w" }
  )
  fs.writeFileSync(
    `./output/${env}/${processName}/${Date.now()}.json`,
    JSON.stringify(output),
    { flag: "w" }
  )
}

export function getSigner(chainId: ChainId): Signer {
  let provider = new ethers.providers.StaticJsonRpcProvider(
    loadChains().find((x: any) => x.chainId == chainId)?.rpc || ""
  )
  let signer = new ethers.Wallet(loadPrivateKey(), provider)
  return signer
}

export function getProvider(chain: ChainInfo): ethers.providers.StaticJsonRpcProvider {
  let provider = new ethers.providers.StaticJsonRpcProvider(
    loadChains().find((x: any) => x.chainId == chain.chainId)?.rpc || ""
  )

  return provider
}

export function getSpokeAddress(chain: ChainInfo): string {
  const thisSpoke = loadSpokes().find(
    (x: any) => x.chainId == chain.chainId
  )?.address
  if (!thisSpoke) {
    throw new Error(
      "Failed to find a spoke contract address on chain " + chain.chainId
    )
  }
  return thisSpoke
}

export function getSpoke(chain: ChainInfo, provider?: ethers.providers.StaticJsonRpcProvider): Spoke {
  const thisSpoke = getSpokeAddress(chain)
  const contract = Spoke__factory.connect(
    thisSpoke,
    provider || getSigner(chain.chainId)
  )
  return contract
}

export function getHubAddress(): string {
  const thisHub = loadHub()?.address
  if (!thisHub) {
    throw new Error(
      "Failed to find a hub contract address"
    )
  }
  return thisHub
}

export function getHub(provider?: ethers.providers.StaticJsonRpcProvider): Hub {
  const chainInfo = loadHub();
  const thisHub = getHubAddress()
  if(!(loadHub().chainId == chainInfo.chainId)) {
    throw new Error("Hub is not on this chain");
  }
  const contract = Hub__factory.connect(
    thisHub,
    provider || getSigner(chainInfo.chainId)
  )
  return contract
}