
  import { tryNativeToHexString, ChainId } from "@certusone/wormhole-sdk"
  import fs from "fs"
  import {ethers, BigNumber} from "ethers";
  import { Hub__factory, Spoke__factory } from "../ts-test/src/ethers-contracts";
  import {deployHub, deploySpoke} from "./helpers/deployments";
  import { getHub, getSpoke, loadChains, loadHub, loadSpokes, init, writeOutputFiles, writeToContracts } from "./helpers/env";

  type ChainInfo = {
    evmNetworkId: number
    chainId: ChainId
    rpc: string
    wormholeAddress: string
    coreRelayerAddress: string
    description: string
  }

  async function run() {
    console.log("-----------------------")
  
    init()

    const chains = loadChains()

    const hub = loadHub();
    const spokes = loadSpokes();
    if (process.argv[2] == "deploy") {
      const chainInfo = chains.find((chain)=>(chain.chainId == parseInt(process.argv[4])));
      if(!chainInfo) {
        console.log("Invalid chain");
      } else {
        const output: any = {
        }
        if (process.argv[3] == "hub") {
          console.log(`Deploying Hub to chain ${chainInfo.chainId}...`);
          const hub = await deployHub(chainInfo);
          console.log(`Hub deployed to ${hub.address} (chain ${hub.chainId})`)
          output.hub = hub;
        } else if (process.argv[3] == "spoke"){
          console.log(`Deploying Spoke to chain ${chainInfo.chainId}...`);
          const spoke = await deploySpoke(chainInfo, "0x" + tryNativeToHexString(loadHub().address, "ethereum"), loadHub().chainId);
          console.log(`Spoke deployed to ${spoke.address} (chain ${spoke.chainId})`)
          output.spoke = spoke
        }
        writeOutputFiles(output, "deployIndividualContract")
        writeToContracts(output);
      }
    } else if (process.argv[2] == "info") {
      console.log("Current chains: ");
      for(let i=0; i<chains.length; i++) {
        console.log(`(${(chains[i].chainId)}): ${chains[i].description}`)
      }
      console.log(`Current Hub: ${hub.chainId}`);
      console.log(`Current Spokes: ${spokes.map((s)=>(s.chainId)).join(", ")}`);
    } else if(process.argv[2] == "spoke") {
      const chainInfo = chains.find((chain)=>(chain.chainId == parseInt(process.argv[3])));
      if(!chainInfo) {
        console.log("Invalid spoke");
      } else {
        const spoke = getSpoke(chainInfo);
        if(process.argv[4] == "getMessages") {
          const result = await spoke.getChatMessages();
          const length = result[1];
          let messages = result[0].slice(0, length);
          if(process.argv.length > 5) {
            messages = messages.slice(-1*parseInt(process.argv[5]));
          }
          for(let i=0; i<messages.length; i++) {
            console.log(`Sender ${messages[i].sender}: ${Buffer.from(messages[i].message.slice(2), "hex")}`);
          }
        } else if(process.argv[4] == "sendMessage") {
          const msg = process.argv[5] 
          try {
            const tx = await spoke.sendChatMessage(Buffer.from(msg), {gasLimit: 5000000, value: BigNumber.from(10).pow(17).mul(2)});
            console.log("Sent message!");
            const rx = await tx.wait();
            console.log("Message confirmed!");
          } catch(err) {
            console.log("Error in sending/confirming message");
            console.log(err)
          }
        } else if(process.argv[4] == "register") {
          try {
            const spokeInfo = spokes.find((s)=>(s.chainId == chainInfo.chainId));
            if(!spokeInfo) {
              console.log("Invalid spoke");
            } else {
              const tx = await getHub().registerEmitter(spokeInfo.chainId, ethers.utils.hexlify("0x"+tryNativeToHexString(spokeInfo.address, "ethereum")));
              console.log("Sent registration message!");
              const rx = await tx.wait();
              console.log("Message confirmed!");
            } 
          } catch(err) {
            console.log("Error in sending/confirming message");
            console.log(err)
          }
        } 
      }
    } else {
        console.log("Welcome to the 'Test xChat Script'!\n");
        console.log("Commands: ")
        console.log("info: Lists all the chains, hub, and spokes")
        console.log("spoke x register: Registers spoke x on the Hub")
        console.log("deploy hub x: Deploys hub on chain x");
        console.log("deploy spoke x: Deploys spoke on chain x");
        console.log("spoke x getMessages: Prints all the messages for spoke x")
        console.log("spoke x getMessages y: Prints the last y messages for spoke x")
        console.log("spoke x sendMessage msg: Sends message consisting of the string 'msg', from spoke x")
    }
    
  }

  run()