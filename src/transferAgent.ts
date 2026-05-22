import { RpcProvider, Account, Contract } from "starknet";
import * as dotenv from "dotenv";

dotenv.config();

// ─── CONFIG ──────────────────────────────────────────────────────────────────
const PROVIDER = new RpcProvider({ nodeUrl: process.env.STARKNET_RPC_URL! });

const ACCOUNT = new Account({
  provider: PROVIDER,
  address: process.env.WALLET_ADDRESS!,
  signer: process.env.PRIVATE_KEY!,
  cairoVersion: "1"
});

// ERC-20 ABI (minimal — only what we need)
const ERC20_ABI = [
  {
    name: "balanceOf",
    type: "function",
    inputs: [{ name: "account", type: "core::starknet::contract_address::ContractAddress" }],
    outputs: [{ name: "balance", type: "core::integer::u256" }],
    state_mutability: "view",
  },
  {
    name: "transfer",
    type: "function",
    inputs: [
      { name: "recipient", type: "core::starknet::contract_address::ContractAddress" },
      { name: "amount", type: "core::integer::u256" },
    ],
    outputs: [{ name: "success", type: "core::bool" }],
    state_mutability: "external",
  },
] as const;

// Execution log store
const executionLog: ExecutionRecord[] = [];

interface ExecutionRecord {
  timestamp: string;
  action: string;
  status: "success" | "skipped" | "error";
  details: string;
}

// ─── 1. FETCH WALLET BALANCE ─────────────────────────────────────────────────
async function fetchWalletBalance(tokenAddress: string): Promise<bigint> {
  const contract = new Contract({ abi: ERC20_ABI, address: tokenAddress, providerOrAccount: PROVIDER });
  const result = await contract.balanceOf(ACCOUNT.address);

  // In starknet.js v9, core::integer::u256 is auto-parsed to a bigint
  const balance = BigInt(typeof result === "bigint" ? result : (result as any).balance);
  console.log(`💰 Balance: ${balance.toString()} (raw units)`);
  return balance;
}

// ─── 2. VALIDATE TRANSFER CONDITION ─────────────────────────────────────────
function validateTransferCondition(balance: bigint, threshold: bigint): boolean {
  const isValid = balance > threshold;
  console.log(`✅ Condition check: ${balance} > ${threshold} = ${isValid}`);
  return isValid;
}

// ─── 3. TRANSFER TOKENS ─────────────────────────────────────────────────────
async function transferTokens(
  tokenAddress: string,
  recipient: string,
  amount: bigint
): Promise<string> {
  const contract = new Contract({ abi: ERC20_ABI, address: tokenAddress, providerOrAccount: ACCOUNT });
  // starknet.js v9 automatically converts bigints to u256 for Cairo 1 contracts
  const call = contract.populate("transfer", { recipient, amount });
  const tx = await ACCOUNT.execute(call);
  await PROVIDER.waitForTransaction(tx.transaction_hash);

  console.log(`🚀 Transfer complete. TX: ${tx.transaction_hash}`);
  return tx.transaction_hash;
}

// ─── 4. CALL ANOTHER AGENT/FUNCTION (COMPOSABILITY) ─────────────────────────
// This is the composability hook — swap in any downstream agent or contract call
async function callNextAgent(txHash: string, context: object): Promise<void> {
  console.log(`🔗 Calling downstream agent with context:`, context);

  // Example: call a notification agent, a DeFi protocol, or another AI agent
  // await notificationAgent.run(context);
  // await anotherContract.method(txHash);

  // For now, we simulate it:
  console.log(`   → Downstream agent received TX: ${txHash}`);
}

// ─── 5. LOG EXECUTION RESULT ─────────────────────────────────────────────────
function logExecutionResult(record: ExecutionRecord): void {
  executionLog.push(record);
  const icon = record.status === "success" ? "✅" : record.status === "skipped" ? "⏭️" : "❌";
  console.log(`${icon} [LOG] ${record.timestamp} | ${record.action} | ${record.details}`);
}

// ─── 6. TRIGGER ALERT ────────────────────────────────────────────────────────
async function triggerAlert(balance: bigint, alertThreshold: bigint): Promise<void> {
  if (balance < alertThreshold) {
    const message = `⚠️  ALERT: Balance ${balance} dropped below threshold ${alertThreshold}!`;
    console.warn(message);

    // Hook your alerting system here:
    // await sendTelegramAlert(message);
    // await sendEmailAlert(message);
    // await postToSlack(message);
  }
}

// ─── MAIN AGENT RUNNER ───────────────────────────────────────────────────────
export async function runTransferAgent(config: {
  tokenAddress: string;         // ERC-20 token contract
  recipient: string;            // Who to send to
  transferAmount: bigint;       // How much to send
  transferThreshold: bigint;    // Only transfer if balance > this
  alertThreshold: bigint;       // Alert if balance drops below this
}) {
  const timestamp = new Date().toISOString();
  console.log(`\n🤖 Transfer Agent starting at ${timestamp}\n`);

  try {
    // Step 1: Fetch balance
    const balance = await fetchWalletBalance(config.tokenAddress);

    // Step 2: Validate condition
    const shouldTransfer = validateTransferCondition(balance, config.transferThreshold);

    if (shouldTransfer) {
      // Step 3: Execute transfer
      const txHash = await transferTokens(
        config.tokenAddress,
        config.recipient,
        config.transferAmount
      );

      // Step 4: Call next agent (composability)
      await callNextAgent(txHash, { balance, txHash, timestamp });

      // Step 5: Log success
      logExecutionResult({
        timestamp,
        action: "TRANSFER",
        status: "success",
        details: `Sent ${config.transferAmount} to ${config.recipient}. TX: ${txHash}`,
      });

      // Step 6: Check post-transfer balance & alert if needed
      const newBalance = await fetchWalletBalance(config.tokenAddress);
      await triggerAlert(newBalance, config.alertThreshold);

    } else {
      // Step 5: Log skip
      logExecutionResult({
        timestamp,
        action: "TRANSFER",
        status: "skipped",
        details: `Balance ${balance} did not exceed threshold ${config.transferThreshold}`,
      });

      // Still check alert even when skipping
      await triggerAlert(balance, config.alertThreshold);
    }

  } catch (err: any) {
    logExecutionResult({
      timestamp,
      action: "TRANSFER",
      status: "error",
      details: err.message,
    });
    throw err;
  }

  console.log(`\n📋 Execution Log:`, executionLog);
}
