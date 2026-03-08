const { createPublicClient, http } = require('viem');
const client = createPublicClient({
  transport: http('https://base-sepolia.g.alchemy.com/v2/a6PmmsjEUZ55ZlTz9quJ1')
});
async function main() {
  const code = await client.getBytecode({
    address: '0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141'
  });
  console.log("CODE:", code ? code.length : "empty");
  const nonce = await client.getTransactionCount({
    address: '0x814a3D96C36C45e92159Ce119a82b3250Aa79E5b'
  });
  console.log("NONCE:", nonce);
}
main().catch(console.error);
