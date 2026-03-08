import { createThirdwebClient } from "thirdweb";

const clientId = process.env.NEXT_PUBLIC_THIRDWEB_CLIENT_ID;

if (!clientId) {
  throw new Error("No client ID provided. Please set NEXT_PUBLIC_THIRDWEB_CLIENT_ID in your .env.local file.");
}

export const client = createThirdwebClient({
  clientId,
});
