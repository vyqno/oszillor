import { inAppWallet, createWallet } from "thirdweb/wallets";

export const wallets = [
  inAppWallet({
    auth: {
      options: ["email", "google", "apple", "passkey"],
    },
  }),
  createWallet("io.metamask"),
  createWallet("com.coinbase.wallet"),
  createWallet("me.rainbow"),
  createWallet("io.rabby"),
];
