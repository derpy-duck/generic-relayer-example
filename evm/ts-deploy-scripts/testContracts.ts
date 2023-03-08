
  import { tryNativeToHexString, ChainId, CONTRACTS, Network } from "@certusone/wormhole-sdk"
  import fs from "fs"
  import {ethers, BigNumber} from "ethers";
  import { Hub__factory, Spoke__factory, IWormholeRelayer__factory } from "../ts-test/src/ethers-contracts";
  import {deployHub, deploySpoke} from "./helpers/deployments";
  import { getHub, getSpoke, loadChains, loadHub, loadSpokes, init, writeOutputFiles, writeToContracts, getSigner } from "./helpers/env";
  import { getDeliveryStatusBySourceTx } from "../../submodules/trustless-generic-relayer/sdk/src/main/status"

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

    const run_deploy = async (args: string[]) => {
      const chainInfo = chains.find((chain)=>(chain.chainId == parseInt(args[4])));
      if(!chainInfo) {
        console.log("Invalid chain");
      } else {
        const output: any = {
        }
        if (args[3] == "hub") {
          console.log(`Deploying Hub to chain ${chainInfo.chainId}...`);
          const hub = await deployHub(chainInfo);
          console.log(`Hub deployed to ${hub.address} (chain ${hub.chainId})`)
          output.hub = hub;
        } else if (args[3] == "spoke"){
          console.log(`Deploying Spoke to chain ${chainInfo.chainId}...`);
          const spoke = await deploySpoke(chainInfo, "0x" + tryNativeToHexString(loadHub().address, "ethereum"), loadHub().chainId);
          console.log(`Spoke deployed to ${spoke.address} (chain ${spoke.chainId})`)
          output.spoke = spoke
        }
        writeOutputFiles(output, "deployIndividualContract")
        writeToContracts(output);
      }
    }

    const run_info = async (args: string[]) => {
      console.log("Current chains: ");
      for(let i=0; i<chains.length; i++) {
        console.log(`(${(chains[i].chainId)}): ${chains[i].description}`)
      }
      console.log(`Current Hub: ${hub.chainId}`);
      console.log(`Current Spokes: ${spokes.map((s)=>(s.chainId)).join(", ")}`);
    }

    const run_hub = async (args: string[]) => {
      const hub = getHub();
      if(args[3] == "state") {
        console.log("Registered spokes:");
      }
    }

    const run_spoke = async (args: string[]) => {
      const chainInfo = chains.find((chain)=>(chain.chainId == parseInt(process.argv[3])));
      if(!chainInfo) {
        console.log("Invalid spoke");
      } else {
        const spoke = getSpoke(chainInfo);
        if(args[4] == "getMessages") {
          const result = await spoke.getChatMessages();
          const length = result[1];
          let messages = result[0].slice(0, length);
          if(args.length > 5) {
            messages = messages.slice(-1*parseInt(process.argv[5]));
          }
          for(let i=0; i<messages.length; i++) {
            console.log(`Sender ${messages[i].sender} (chain ${messages[i].chainId}): ${Buffer.from(messages[i].message.slice(2), "hex")}`);
          }
        } else if(args[4] == "sendMessage") {
          const msg = args[5] 
          const value = args.length > 6 ? BigNumber.from(args[6]) : BigNumber.from(10).pow(17).mul(2)
          try {
            const tx = await spoke.sendChatMessage(Buffer.from(msg), {gasLimit: 5000000, value});
            console.log("Sent message!");
            console.log(`Transaction hash: ${tx.hash}`)
            const rx = await tx.wait();
            console.log("Message confirmed!");
            
          } catch(err) {
            console.log("Error in sending/confirming message");
            console.log(err)
          }
        } else if(args[4] == "register") {
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
        } else if(args[4] == "status") {
          const txHash = args[5];
          const status = await getDeliveryStatusBySourceTx("TESTNET", chainInfo.chainId, spoke.provider, txHash, 1, hub.chainId, getHub().provider);
          if(status.length == 0) console.log("No delivery status found.. are your inputs valid?");
          else {
            console.log(`Relay Request found\nStatus: ${status[0].status}`);
          }
        } else if(args[4] == "resend") {
          const txHash = args[5];
          const coreRelayer = IWormholeRelayer__factory.connect(chainInfo.coreRelayerAddress, getSigner(chainInfo.chainId));
          const relayProvider = await coreRelayer.getDefaultRelayProvider();
          const value = args.length > 6 ? BigNumber.from(args[6]) : BigNumber.from(10).pow(17).mul(2)
          const tx = await coreRelayer.resend({
            sourceChain: chainInfo.chainId,
            sourceTxHash: txHash,
            sourceNonce: 1,
            targetChain: hub.chainId,
            deliveryIndex: 1,
            multisendIndex: 0,
            newMaxTransactionFee: value,
            newReceiverValue: 0,
            newRelayParameters: coreRelayer.getDefaultRelayParams()
          }, relayProvider, {gasLimit: 5000000, value });
          console.log("Message requesting redelivery sent");
          console.log(`Transaction hash: ${tx.hash}`)
          await tx.wait();
          console.log("Message confirmed!")

        }
      }
    }

    const run_help = () => {
        console.log("Welcome to the 'Test xChat Script'!\n");
        console.log("Commands: ")
        console.log("help: Prints this help message")
        console.log("info: Lists all the chains, hub, and spokes")
        console.log("spoke [x] register: Registers spoke x on the Hub")
        console.log("deploy hub [x]: Deploys hub on chain x");
        console.log("deploy spoke [x]: Deploys spoke on chain x");
        console.log("spoke [x] getMessages: Prints all the messages for spoke x")
        console.log("spoke [x] getMessages y: Prints the last y messages for spoke x")
        console.log("spoke [x] sendMessage [msg]: Sends message consisting of the string 'msg', from spoke x")
        console.log("spoke [x] status [txHash]: Prints status of the sent message from spoke x correponding to the transaction hash 'txHash'")
        console.log("spoke [x] resend [txHash]: Redeliver the sent message from spoke x corresponding to the transaction hash 'txHash'")
        console.log("hub state: Read hub state");
      }
      if (process.argv.length < 3) {
        run_help()
      } else if (process.argv[2] == "deploy") {
        run_deploy(process.argv)
      } else if (process.argv[2] == "info") {
        run_info(process.argv)
      } else if(process.argv[2] == "spoke") {
        run_spoke(process.argv)
      } else if(process.argv[2] == "help")  {
        run_help()
      } else if(process.argv[2] == "hub") {
        run_hub(process.argv)
      } else {
        console.log("Invalid command")
      }
    
    
  }

  run()