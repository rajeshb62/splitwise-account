import {
    AccountWallet,
    createDebugLogger,
    Fr,
    PXE,
    DebugLogger,
    AztecAddress,
    GrumpkinScalar,
    Wallet,
    PartialAddress,
  } from "@aztec/aztec.js";
  import { type DeployAccountOptions } from "@aztec/aztec.js";
  import {
    AccountGroupContractArtifact,
    AccountGroupContract,
  } from "../src/circuits/src/artifacts/AccountGroup.js";
  import { AccountGroupManager, AccountGroupContractClass } from "./types.js";
  import {
    delay,
    createSchnorrAccount,
    generatePublicKeys,
    setupSandbox,
  } from "./utils.js";
  
  const { PXE_URL1 = "http://localhost:8080" } = process.env;
  const { PXE_URL2 = "http://localhost:8081" } = process.env;
  const { PXE_URL3 = "http://localhost:8082" } = process.env;
  
  // Test case to deploy the contract
  describe("AccountGroup Contract Deployment", () => {
    //PXE instances
    let pxe1: PXE;
    let pxe2: PXE;
    let pxe3: PXE;
    console.log("we begin");
    //Logger
    let logger: DebugLogger;
  
    //Wallets
    let ownerAccount: AccountWallet;
    let aliceWallet: Wallet;
    let bobWallet: Wallet;
    let charlieWallet: Wallet;
  
    //Addresses
    let contractAddressPXE1: AztecAddress;
    let owner: AztecAddress;
    let aliceAddress: AztecAddress;
    let bobAddress: AztecAddress;
    let charlieAddress: AztecAddress;
  
    //Keys
    let accountPrivateKey: GrumpkinScalar;
    let contractAddressPXE2: AztecAddress;
    let contractAddressPXE3: AztecAddress;
    let salt: Fr;
    let secret: Fr;
  
    //Contract instances and Wallets
    let contractAccountPXE1: Wallet;
    let contractAccountPXE2: Wallet;
    let contractAccountPXE3: Wallet;
    let contractInstancePXE1: AccountGroupContract;
    let contractInstancePXE2: AccountGroupContract;
    let contractInstancePXE3: AccountGroupContract;
  
    let partialAddress: Fr;
  
    //Contract Class
    let accountContractPXE1: AccountGroupContractClass;
  
    //-----------------------------------Setup-----------------------------------
  
    beforeAll(async () => {
      console.log("we begin");
      //Initialiing the Logger
      logger = createDebugLogger("aztec:account-group");
      console.log("we begin");
      //Setting up the PXE instances
      pxe1 = await setupSandbox(PXE_URL1);
      pxe2 = await setupSandbox(PXE_URL2);
      pxe3 = await setupSandbox(PXE_URL3);
  
      //Creating the owner account on PXE1
      ownerAccount = await createSchnorrAccount(pxe1);
      owner = ownerAccount.getAddress();
  
      //Creating Alice's account on PXE2
      aliceWallet = await createSchnorrAccount(pxe2);
      aliceAddress = aliceWallet.getAddress();
  
      //Creating Bob's account on PXE3
      bobWallet = await createSchnorrAccount(pxe3);
      bobAddress = bobWallet.getAddress();
  
      //Creating Charlie's account on PXE1, (not added to the group)
      charlieWallet = await createSchnorrAccount(pxe1);
      charlieAddress = charlieWallet.getAddress();
    });
  

  //-----------------------------------Registering accounts on PXEs -----------------------------------

  it("Deploys the AccountGroupContract", async () => {
    //Generate random salt and secret for account deploymnet
    salt = Fr.random();
    secret = Fr.random();

    //Generate public and private keys for the account contract
    const { signingPrivateKey, x, y } = await generatePublicKeys();
    accountPrivateKey = signingPrivateKey;

    //Create an instance of the AccountGroupContractClass with the signing private key and owner address
    accountContractPXE1 = new AccountGroupContractClass(
      signingPrivateKey,
      owner
    );

    // Initialize AccountGroupManager with the contract.
    const accountManagerPXE1 = new AccountGroupManager(
      pxe1,
      secret,
      accountContractPXE1,
      owner,
      salt
    );

    //Register the account contract in PXE1
    await accountManagerPXE1.register();

    // Deployment options for the account
    const deployOptions: DeployAccountOptions = {
      skipClassRegistration: false,
      skipPublicDeployment: false,
    };

    //Deploy the account and get the wallet instance
    const deployTx = accountManagerPXE1.deploy(deployOptions);
    const walletPXE1 = await deployTx.getWallet();
    contractAccountPXE1 = walletPXE1;
    contractAddressPXE1 = walletPXE1.getAddress();

    //this is not used, just a check
    partialAddress = walletPXE1.getCompleteAddress().partialAddress;
    console.log("partialAddress", partialAddress.toString());

    //Create an instance of the contract in PXE1
    //Using the account contracts associated wallet to call methods on the contract
    contractInstancePXE1 = await AccountGroupContract.at(
      contractAddressPXE1,
      contractAccountPXE1
    );

    expect(walletPXE1.getCompleteAddress()).toBeDefined();

    //Delay to ensure sychronization
    await delay(2000);
  });

  it("Registers the AccountGroupContract in Alice's PXE", async () => {
    //This initializes the Account Contract in the Second PXE instance, using the same secret and salt
    //These are the two secrets that need to be known to register the contract in a new PXE instance
    const aliceManagerPXE2 = new AccountGroupManager(
      pxe2,
      secret,
      accountContractPXE1,
      owner,
      salt
    );

    // Register contract wallet in Alice’s PXE
    await aliceManagerPXE2.register();
    const walletPXE2 = await aliceManagerPXE2.getWallet();
    contractAccountPXE2 = walletPXE2;
    contractAddressPXE2 = walletPXE2.getAddress();

    //Ensure the contract addresses match across the PXE instances
    expect(walletPXE2.getCompleteAddress().address.toString()).toBe(
      contractAddressPXE1.toString()
    );
    expect(walletPXE2.getCompleteAddress().toString()).toBeDefined();

    //Create an instance of the contract in PXE2
    contractInstancePXE2 = await AccountGroupContract.at(
      contractAddressPXE2,
      contractAccountPXE2
    );

    //Getting the block number for tracking purposes
    const blockNumber = await pxe1.getBlockNumber();
    console.log("blockNumber", blockNumber);
    await delay(2000);
  });

  it("Registers the AccountGroupContract in Bob's PXE", async () => {
    //Initialize the Account Contract for Bob in PXE3
    const bobManagerPXE3 = new AccountGroupManager(
      pxe3,
      secret,
      accountContractPXE1,
      owner,
      salt
    );

    //Register the contract wallet in Bob's PXE
    await bobManagerPXE3.register();
    const walletPXE3 = await bobManagerPXE3.getWallet();
    contractAccountPXE3 = walletPXE3;
    contractAddressPXE3 = walletPXE3.getAddress();

    contractInstancePXE3 = await AccountGroupContract.at(
      contractAddressPXE3,
      contractAccountPXE3
    );

    //Ensure the contract addresses match across the PXE instances
    expect(walletPXE3.getCompleteAddress().address.toString()).toBe(
      contractAddressPXE1.toString()
    );
  });

  it("Makes balance between Alice and Bob PXE1", async () => {
    //Add Alice and Bob to the group, from different PXE instances
    await contractInstancePXE1.methods.add_member(aliceAddress).send().wait();
    await contractInstancePXE2.methods.add_member(bobAddress).send().wait();
    
    const set_balance = await contractInstancePXE1.methods
      .set_balance(aliceAddress, bobAddress, 100)
      .send()
      .wait();
    console.log("set_balance", set_balance);

    const balance = await contractInstancePXE1.methods
      .get_balance(aliceAddress, bobAddress)
      .simulate();
    console.log("balance", balance);
    expect(balance).toBe(100n);
  });

  it("Makes balance between Alice and Bob PXE2", async () => {
    const set_balance = await contractInstancePXE2.methods
      .set_balance(aliceAddress, bobAddress, 100)
      .send()
      .wait();
    console.log("set_balance", set_balance);

    const balance = await contractInstancePXE2.methods
      .get_balance(aliceAddress, bobAddress)
      .simulate();
    console.log("balance", balance);
    expect(balance).toBe(200n);
  });

  it("Makes balance between Alice and Bob PXE3", async () => {
    const set_balance = await contractInstancePXE3.methods
      .set_balance(aliceAddress, bobAddress, 100)
      .send()
      .wait();
    console.log("set_balance", set_balance);

    const balance = await contractInstancePXE3.methods
      .get_balance(aliceAddress, bobAddress)
      .simulate();
    console.log("balance", balance);
    expect(balance).toBe(300n);
  });
});

