import { getSchnorrAccount } from "@aztec/accounts/schnorr";
import {
  AztecAddress,
  createPXEClient,
  Fr,
  GrumpkinScalar,
  PXE,
  Schnorr,
} from "@aztec/aztec.js";
import { waitForPXE } from "@aztec/aztec.js";

/**
 * Sets up a PXE instance at the given URL.
 *
 * @param PXE_URL - The URL of the PXE instance.
 * @returns {Promise<PXE>} A promise that resolves to the PXE instance.
 */
export const setupSandbox = async (PXE_URL: string): Promise<PXE> => {
  try {
    console.log("Connecting to PXE at:", PXE_URL);
    const pxe = createPXEClient(PXE_URL);
    
    console.log("Waiting for PXE...");
    await waitForPXE(pxe);
    
    // Check if we can get block number as a connection test
    const blockNumber = await pxe.getBlockNumber();
    console.log("Connected to PXE, current block:", blockNumber);
    
    return pxe;
  } catch (error) {
    console.error("Error setting up PXE:", error);
    console.error("PXE URL:", PXE_URL);
    throw error;
  }
};

/**
 * Generates a Schnorr account for testing purposes, creating secret and signing keys.
 *
 * @param pxe - The PXE instance used to create the Schnorr account.
 * @returns {Promise<any>} A promise that resolves to the Schnorr wallet.
 */
export const createSchnorrAccount = async (pxe: PXE) => {
  try {
    // Check connection by getting block number
    const blockNumber = await pxe.getBlockNumber();
    console.log("PXE connected at block:", blockNumber);

    const secret = Fr.random();
    console.log("Generated secret:", secret.toString());

    const signingPrivateKey = GrumpkinScalar.random();
    console.log("Generated signing key:", signingPrivateKey.toString());

    // Add explicit await and error handling for account creation
    const schnorrAccount = getSchnorrAccount(pxe, secret, signingPrivateKey);
    console.log("Account created, waiting for setup...");
    
    const wallet = await schnorrAccount.waitSetup();
    console.log("Wallet setup complete");
    
    return wallet;
  } catch (error) {
    console.error("Error in createSchnorrAccount:", error);
    throw error;
  }
};

/**
 * Generates Schnorr public keys for a Schnorr account contract.
 *
 * @returns {Promise<{signingPrivateKey: GrumpkinScalar, x: Fr, y: Fr}>}
 * An object containing the signing private key and the public key components (x, y).
 */
export const generatePublicKeys = async () => {
  const signingPrivateKey = GrumpkinScalar.random(); // Generates a random Schnorr signing private key.
  const schnorr = new Schnorr();

  // Computes the Schnorr public key.
  const publicKey = schnorr.computePublicKey(signingPrivateKey);

  // Returns the public key fields (x, y).
  const [x, y] = publicKey.toFields();
  return { signingPrivateKey, x, y };
};

export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}