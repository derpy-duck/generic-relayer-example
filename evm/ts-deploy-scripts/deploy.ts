
  import { tryNativeToHexString, ChainId } from "@certusone/wormhole-sdk"
  import fs from "fs"
  import {ethers} from "ethers";
  import { Hub__factory, Spoke__factory } from "../ts-test/src/ethers-contracts";
  import {deployHub, deploySpoke} from "./helpers/deployments";
  import { writeOutputFiles, loadChains, init, loadHub, getHub } from "./helpers/env";

  type ChainInfo = {
    evmNetworkId: number
    chainId: ChainId
    rpc: string
    wormholeAddress: string
    coreRelayerAddress: string
    description: string
  }

  

  async function run() {
    console.log("Start deploy!")
  
    init()

    const chains = loadChains()

    const output: any = {
      spokes: []
    }
    
    console.log(`Deploying Hub on chain 0 ...`);
    const hub = await deployHub(chains[0])
    output.hub = hub;
    for (let i = 0; i < 2; i++) {
      console.log(`Deploying Spoke for chain ${chains[i].chainId} ...`)
      const spoke = await deploySpoke(chains[i], "0x" + tryNativeToHexString(hub.address, "ethereum"), hub.chainId)
      await getHub().registerEmitter(spoke.chainId, ethers.utils.hexlify("0x"+tryNativeToHexString(spoke.address, "ethereum"))).then((t)=>t.wait);
      output.spokes.push(spoke)
    }
  
    writeOutputFiles(output, "deployHubAndSpokes")
  }

  run().then(() => console.log("Done deploying!"))
