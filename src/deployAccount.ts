import { RpcProvider, Account, stark, ec, hash, CallData, constants } from "starknet";
import * as dotenv from "dotenv";

dotenv.config();

// ─── DEPLOY ACCOUNT ON SEPOLIA ───────────────────────────────────────────────
// This script deploys an OpenZeppelin account contract using your private key.
// It uses STRK for gas fees (V3 transaction).

const PROVIDER = new RpcProvider({ nodeUrl: process.env.STARKNET_RPC_URL! });

// OpenZeppelin Account class hash on Sepolia
// This is the standard OZ Account v0.14.0 class hash
const OZ_ACCOUNT_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f";

async function deployAccount() {
  const privateKey = process.env.PRIVATE_KEY!;
  
  // Derive public key from private key
  const publicKey = ec.starkCurve.getStarkKey(privateKey);
  console.log(`🔑 Public Key: ${publicKey}`);

  // Compute the expected account address
  const constructorCalldata = CallData.compile({ public_key: publicKey });
  const computedAddress = hash.calculateContractAddressFromHash(
    publicKey,  // salt
    OZ_ACCOUNT_CLASS_HASH,
    constructorCalldata,
    0  // deployer address (0 = not deployed via factory)
  );
  console.log(`📍 Computed Address: ${computedAddress}`);
  console.log(`📍 Your .env Address: ${process.env.WALLET_ADDRESS}`);

  // Check if the computed address matches your .env address
  const envAddr = BigInt(process.env.WALLET_ADDRESS!);
  const compAddr = BigInt(computedAddress);
  
  if (envAddr !== compAddr) {
    console.log(`\n⚠️  Address mismatch! Your wallet was likely created with a different class hash.`);
    console.log(`   Computed: ${computedAddress}`);
    console.log(`   .env:     ${process.env.WALLET_ADDRESS}`);
    console.log(`\n   Trying alternative class hashes...`);
    
    // Try common alternative class hashes
    const alternatives = [
      { name: "OZ Account v0.8.1", hash: "0x05400e90f7b74d3fefba034769e661802e4f8f2ab0efbb1a0bd1dc3b82b48e5e" },
      { name: "OZ Account v0.9.0", hash: "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003" },
      { name: "OZ Account v0.11.0", hash: "0x04c6d6cf894f8bc96bb9c525e6853e5483177841f7388f74a46cfda6f028c755" },
      { name: "OZ Account v0.13.0", hash: "0x00e2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6" },
      { name: "Argent Account", hash: "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f" },
      { name: "Braavos Account", hash: "0x00816dd0297efc55dc1e7559020a3a825e81ef734b558f03c83325d4da7e6253" },
    ];
    
    for (const alt of alternatives) {
      const altAddr = hash.calculateContractAddressFromHash(
        publicKey,
        alt.hash,
        CallData.compile({ public_key: publicKey }),
        0
      );
      if (BigInt(altAddr) === envAddr) {
        console.log(`\n✅ Match found: ${alt.name} (${alt.hash})`);
        console.log(`   Use this class hash to deploy.`);
        
        // Deploy with this class hash
        await doDeployAccount(privateKey, publicKey, alt.hash, altAddr);
        return;
      }
    }
    
    console.log(`\n❌ Could not match your address to any known class hash.`);
    console.log(`   Your account may have been created with a custom salt or class hash.`);
    console.log(`   Please check which wallet (ArgentX, Braavos, etc.) generated this address.`);
    return;
  }

  await doDeployAccount(privateKey, publicKey, OZ_ACCOUNT_CLASS_HASH, computedAddress);
}

async function doDeployAccount(privateKey: string, publicKey: string, classHash: string, address: string) {
  console.log(`\n🚀 Deploying account at ${address}...`);
  
  const account = new Account({ provider: PROVIDER, address, signer: privateKey });
  
  const constructorCalldata = CallData.compile({ public_key: publicKey });
  
  try {
    const deployResponse = await account.deployAccount({
      classHash: classHash,
      constructorCalldata: constructorCalldata,
      addressSalt: publicKey,
    });
    
    console.log(`📝 Deploy TX Hash: ${deployResponse.transaction_hash}`);
    console.log(`⏳ Waiting for confirmation...`);
    
    await PROVIDER.waitForTransaction(deployResponse.transaction_hash);
    console.log(`✅ Account deployed successfully!`);
    console.log(`   Address: ${deployResponse.contract_address}`);
  } catch (err: any) {
    console.error(`❌ Deployment failed: ${err.message}`);
    
    if (err.message.includes("Contract not found") || err.message.includes("Invalid block")) {
      console.log(`\n💡 Tip: The account may need ETH or STRK for deployment gas.`);
      console.log(`   Your balance: 800 STRK, 0 ETH`);
      console.log(`   Try getting some Sepolia ETH from a faucet first.`);
    }
  }
}

deployAccount().catch(console.error);
