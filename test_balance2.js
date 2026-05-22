const { RpcProvider, Contract, uint256 } = require("starknet");

const ABI = [{
    name: "balanceOf",
    type: "function",
    inputs: [{ name: "account", type: "core::starknet::contract_address::ContractAddress" }],
    outputs: [{ name: "balance", type: "core::integer::u256" }],
    state_mutability: "view",
}];

const STRK_ADDR = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
const WALLET = "0x02f03858800b1f0a367ff544094984bE118Ebef1b1BC319cB84148CC2D05D070";

async function check(name, url) {
    const provider = new RpcProvider({ nodeUrl: url });
    const contract = new Contract(ABI, STRK_ADDR, provider);
    try {
        const res = await contract.balanceOf(WALLET);
        console.log(`${name}: ${uint256.uint256ToBN(res.balance).toString()}`);
    } catch(e) {
        console.log(`${name} error:`, e.message);
    }
}

async function main() {
    await check("Sepolia (Cartridge)", "https://api.cartridge.gg/x/starknet/sepolia");
}
main();
