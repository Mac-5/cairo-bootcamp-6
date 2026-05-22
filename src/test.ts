import { RpcProvider, Contract } from "starknet";
import * as dotenv from "dotenv";

dotenv.config();

const PROVIDER = new RpcProvider({ nodeUrl: process.env.STARKNET_RPC_URL! });
const ERC20_ABI = [
  {
    name: "balanceOf",
    type: "function",
    inputs: [{ name: "account", type: "core::starknet::contract_address::ContractAddress" }],
    outputs: [{ name: "balance", type: "core::integer::u256" }],
    state_mutability: "view",
  }
] as const;

async function test() {
  const contract = new Contract({ abi: ERC20_ABI, address: "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d", providerOrAccount: PROVIDER });
  const result = await contract.balanceOf(process.env.WALLET_ADDRESS!);
  console.log("RESULT TYPE:", typeof result);
  console.log("RESULT:", result);
}
test();
