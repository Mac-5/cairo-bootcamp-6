import { RpcProvider, Account, ec, hash, CallData, num } from "starknet";
import * as dotenv from "dotenv";

dotenv.config();

const PROVIDER = new RpcProvider({ nodeUrl: process.env.STARKNET_RPC_URL! });
const TARGET_ADDRESS = BigInt(process.env.WALLET_ADDRESS!);

async function findAndDeploy() {
  const privateKey = process.env.PRIVATE_KEY!;
  const publicKey = ec.starkCurve.getStarkKey(privateKey);
  console.log(`🔑 Public Key: ${publicKey}`);
  console.log(`🎯 Target Address: ${process.env.WALLET_ADDRESS}\n`);

  // ArgentX class hashes (Sepolia + Mainnet, various versions)
  const argentClassHashes = [
    { name: "Argent v0.4.0", hash: "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f" },
    { name: "Argent v0.3.1", hash: "0x029927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b" },
    { name: "Argent v0.3.0", hash: "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003" },
    { name: "Argent v0.3.1 alt", hash: "0x1a7820094feaf82d53f53f214b81292d717e7bb9a92bb2488092cd306f3993f" },
    { name: "Argent Sepolia latest", hash: "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f" },
    { name: "Argent Cairo 1.0 v1", hash: "0x01148c31dfa5c4708a4e9cf1f2d3b26e8812c177bda19150757ca3ff74a4e3a0" },
    { name: "Argent Cairo 1.0 v2", hash: "0x023371b227eaecd8e8920cd429d2cd0f3fee6abaacca08d3ab82a7cdd", hash2: "0x05400e90f7b74d3fefba034769e661802e4f8f2ab0efbb1a0bd1dc3b82b48e5e" },
  ];

  // Constructor formats to try
  const constructorFormats = [
    { name: "(owner, guardian=0)", build: () => CallData.compile({ owner: publicKey, guardian: "0" }) },
    { name: "(signer, guardian=0)", build: () => CallData.compile({ signer: publicKey, guardian: "0" }) },
    { name: "(public_key)", build: () => CallData.compile({ public_key: publicKey }) },
    { name: "[publicKey, 0]", build: () => [publicKey, "0"] },
    { name: "[publicKey]", build: () => [publicKey] },
  ];

  // Salt options
  const salts = [
    { name: "publicKey", value: publicKey },
    { name: "0", value: "0" },
  ];

  console.log(`🔍 Trying ${argentClassHashes.length} class hashes × ${constructorFormats.length} constructors × ${salts.length} salts...\n`);

  for (const ch of argentClassHashes) {
    for (const cf of constructorFormats) {
      for (const salt of salts) {
        try {
          const calldata = cf.build();
          const computed = hash.calculateContractAddressFromHash(
            salt.value,
            ch.hash,
            calldata,
            0
          );

          if (BigInt(computed) === TARGET_ADDRESS) {
            console.log(`✅ MATCH FOUND!`);
            console.log(`   Class Hash: ${ch.name} (${ch.hash})`);
            console.log(`   Constructor: ${cf.name}`);
            console.log(`   Salt: ${salt.name}`);
            console.log(`   Address: ${computed}\n`);

            // Now deploy
            console.log(`🚀 Deploying account...`);
            const account = new Account({ provider: PROVIDER, address: computed, signer: privateKey });

            const deployResponse = await account.deployAccount({
              classHash: ch.hash,
              constructorCalldata: calldata,
              addressSalt: salt.value,
            });

            console.log(`📝 TX Hash: ${deployResponse.transaction_hash}`);
            console.log(`⏳ Waiting for confirmation...`);
            await PROVIDER.waitForTransaction(deployResponse.transaction_hash);
            console.log(`✅ Account deployed successfully at ${deployResponse.contract_address}!`);
            return;
          }
        } catch {
          // Skip invalid combinations silently
        }
      }
    }
  }

  console.log(`❌ No match found with standard ArgentX class hashes.`);
  console.log(`\n💡 Your best options:`);
  console.log(`   1. Open Ready Wallet (ArgentX) in your browser`);
  console.log(`   2. Make ANY transaction from it (even a 0 STRK transfer to yourself)`);
  console.log(`   3. This will auto-deploy the account contract`);
  console.log(`   4. Then the transfer agent script will work!\n`);
  console.log(`   OR: Use 'sncast account create' to make a new compatible wallet.`);
}

findAndDeploy().catch(console.error);
