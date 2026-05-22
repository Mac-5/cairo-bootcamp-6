import { runTransferAgent } from "./transferAgent";
import * as dotenv from "dotenv";

dotenv.config();

runTransferAgent({
  tokenAddress: "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d", // STRK on StarkNet
  recipient: process.env.RECIPIENT_ADDRESS!,
  transferAmount:   BigInt("1000000000000000"),    // 0.001 ETH in wei
  transferThreshold: BigInt("5000000000000000"),   // only transfer if balance > 0.005 ETH
  alertThreshold:    BigInt("2000000000000000"),   // alert if balance < 0.002 ETH
});
