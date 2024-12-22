mod notes;
mod helpers;

use dep::aztec::macros::aztec;
#[aztec]
contract AccountGroup {

    use dep::aztec::{prelude::{Map, AztecAddress, PrivateContext, PrivateImmutable, PrivateSet}, 
                    encrypted_logs::encrypted_note_emission::{encode_and_encrypt_note, encode_and_encrypt_note_unconstrained},
                    keys::getters::get_public_keys,
                    oracle::get_nullifier_membership_witness::get_low_nullifier_membership_witness,
                    macros::{storage::storage, functions::{private, initializer, view, noinitcheck}},
                    note::note_getter::NoteGetterOptions
                    };
    use dep::authwit::{
        entrypoint::{app::AppPayload, fee::FeePayload}, account::AccountActions,
        auth_witness::get_auth_witness
    };

    // use value_note::{balance_utils, utils::{increment, decrement}, value_note::ValueNote};
    use crate::notes::{public_key_note::PublicKeyNote, NewAddressNote::NewAddressNote};
    use crate::helpers::{increment, decrement, membership_check, membership_check_multiple};
    use value_note::{value_note::ValueNote};
    use std::hash::poseidon2;

    global ZERO_ADDRESS: AztecAddress = AztecAddress::from_field(0x0000000000000000000000000000000000000000000000000000000000000000);

    #[storage]
  struct Storage<Context> {
      signing_public_key: PrivateImmutable<PublicKeyNote, Context>, //Stores the public key for the Schnorr account (immutably)
      group_members: PrivateSet<NewAddressNote, Context>, //Stores the group members (privately)
      member_balances : Map<Field, PrivateSet<ValueNote, Context>, Context>, //Stores the balances of the group members (privately)
  }

/**
    * Constructor: Initializes the contract with a signing public key, owner address
    *
    * @param signing_pub_key_x - The x coordinate of the public key for the Schnorr signature
    * @param signing_pub_key_y - The y coordinate of the public key for the Schnorr signature
    * @param owner - The owner address
    */
  #[private]
#[initializer]
fn constructor(signing_pub_key_x: Field, signing_pub_key_y: Field, owner: AztecAddress) {
    let this = context.this_address();
    let this_keys = get_public_keys(this);
    //not emitting outgoing for msg_sender here to not have to register keys for the contract through which we deploy this (typically MultiCallEntryPoint).

    //Create the public key note for the Schnorr Account
    let mut pub_key_note = PublicKeyNote::new(signing_pub_key_x, signing_pub_key_y, this_keys.npk_m.hash());
    storage.signing_public_key
        .initialize(&mut pub_key_note)
        .emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            this_keys.ovpk_m,
            this_keys.ivpk_m,
            this
        ));

    //Add the owner to the group members set.
    let mut owner_member_note = NewAddressNote::new(owner, this_keys.npk_m.hash());
    storage.group_members
        .insert(&mut owner_member_note)
        .emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            this_keys.ovpk_m,
            this_keys.ivpk_m,
            owner
        )
    );
}

/**
* Entrypoint function to initialize actions for the Schnorr Account
* Can make this do nothing as this contract is not meant to interact with anything, just to store state. 
*/
 #[private]
fn entrypoint(app_payload: AppPayload, fee_payload: FeePayload, cancellable: bool) {
    // assert(false, "This contract is not meant to be interacted with");
    let actions = AccountActions::init(&mut context, is_valid_impl);
    actions.entrypoint(app_payload, fee_payload, cancellable);
}

/**
     * Adds a member to the group.
     * In the future this can be improved to send the member a note to register in their PXE, currently not possible with the current note system.
     * 
     * @param member - Aztec address of the new group member.
     */
#[private]
 fn add_member(member: AztecAddress) {
     let contract_address = context.this_address();
     assert(context.msg_sender() == contract_address, "Only the contract can call this function");
     let contract_address_keys = get_public_keys(contract_address);
     let mut member_address_note = NewAddressNote::new(member, contract_address_keys.npk_m.hash());
     storage.group_members.insert(&mut member_address_note).emit(
         encode_and_encrypt_note_unconstrained(
             &mut context,
             contract_address_keys.ovpk_m,
             contract_address_keys.ivpk_m,
             member
         )
     );
 }

/**
     * View a specific group member at a given position.
     * This is a workarounf for testing purposes
     * 
     * @param position - Index of the group member to view.
     * @returns {AztecAddress} The Aztec address of the member, or ZERO_ADDRESS if out of bounds.
     */
    #[private]
    #[view]
    fn view_member(position: u32) -> AztecAddress {
        let contract_address = context.this_address();
        let contract_address_keys = get_public_keys(contract_address);
        let options = NoteGetterOptions::new();
        let members_notes: BoundedVec<NewAddressNote, 16> = storage.group_members.get_notes(options);

        if position < members_notes.len() as u32 {
            let note = members_notes.get_unchecked(position as u32);
            note.address
        } else {
            ZERO_ADDRESS
        };
    }
/**
     * Sets up shared payments between a creditor and debtors.
     * 
     * @param creditor - The creditor's Aztec address.
     * @param debtors - An array of debtor Aztec addresses.
     * @param amount - The amount to distribute between the debtors.
     */
    #[private]
    fn setup_group_payments(creditor: AztecAddress, debtors: [AztecAddress; 2], amount: Field) {
        let contract_address = context.this_address();
        assert(context.msg_sender() == contract_address, "Only the contract can call this function");
        assert(membership_check_multiple(creditor, debtors, contract_address, storage.group_members), "Creditor or debtors are not in the group");

        let shared_amount : u32 = amount as u32 / (debtors.len() + 1);
        for i in 0..2 {
            let debtor = debtors[i];
            let hash_inputs = [creditor.to_field(), debtor.to_field()];
            let key = poseidon2::Poseidon2::hash(hash_inputs, 2);

            let storage_location = storage.member_balances.at(key);
            //Using the ValueNote helpers to increment the balance
            increment(
                storage_location,
                shared_amount.to_field(),
                contract_address,
                contract_address
            );
        }
    }

    /**
     * Sets the balance between a creditor and a debtor.
     * 
     * @param creditor - The creditor's Aztec address.
     * @param debtor - The debtor's Aztec address.
     * @param amount - The amount of the balance.
     */
    #[private]
    fn set_balance(creditor: AztecAddress, debtor: AztecAddress, amount: Field) {
    let contract_address = context.this_address();
    assert(context.msg_sender() == contract_address, "Only the contract can call this function");
    let location = storage.group_members;
    assert(membership_check(creditor, debtor, contract_address, location), "Creditor or debtor are not in the group");

    let hash_inputs = [creditor.to_field(), debtor.to_field()];
    let key = poseidon2::Poseidon2::hash(hash_inputs, 2);

    let storage_location = storage.member_balances.at(key);
    increment(storage_location, amount, contract_address, contract_address);
    }
    /**
     * Processes a payment from a debtor to a creditor.
     * 
     * @param debtor - The debtor's Aztec address.
     * @param creditor - The creditor's Aztec address.
     * @param amount - The payment amount.
     */
    #[private]
    fn make_payment(debtor: AztecAddress, creditor: AztecAddress, amount: Field) {
        let contract_address = context.this_address();
        assert(context.msg_sender() == contract_address, "Only the contract can call this function");
        let location = storage.group_members;
        assert(membership_check(creditor, debtor, contract_address, location), "Creditor or debtor are not in the group");

        let hash_inputs = [creditor.to_field(), debtor.to_field()];
        let key = poseidon2::Poseidon2::hash(hash_inputs, 2);

        let storage_location = storage.member_balances.at(key);
        decrement(storage_location, amount, contract_address, contract_address);
    }



  #[private]
#[view]
fn get_balance(creditor: AztecAddress, debtor: AztecAddress) -> Field {
    let contract_address = context.this_address();
    assert(context.msg_sender() == contract_address, "Only the contract can call this function");

    let hash_inputs = [creditor.to_field(), debtor.to_field()];
    let key = poseidon2::Poseidon2::hash(hash_inputs, 2);

    let options = NoteGetterOptions::new();
    let balance_notes: BoundedVec<ValueNote, 16> = storage.member_balances.at(key).get_notes(options);

    let mut total_balance = 0 as Field;
    for i in 0..balance_notes.max_len() {
        if i < balance_notes.len() {
            let note = balance_notes.get_unchecked(i);
            total_balance += note.value;
        }
    }
    total_balance
}

/**
     * Verifies an authorization witness using a private signature.
     * 
     * @param inner_hash - The inner hash for authentication.
     * @returns {Field} A field representing the verification result.
     */
    #[private]
    #[view]
    fn verify_private_authwit(inner_hash: Field) -> Field {
        let actions = AccountActions::init(&mut context, is_valid_impl);
        actions.verify_private_authwit(inner_hash)
    }
/**
     * Verifies if the provided signature is valid for the account.
     * 
     * @param context - The private context of the contract.
     * @param outer_hash - The hash used for signature verification.
     * @returns {bool} True if the signature is valid, false otherwise.
     */
    #[contract_library_method]
    fn is_valid_impl(context: &mut PrivateContext, outer_hash: Field) -> bool {
        let storage = Storage::init(context);
        let public_key = storage.signing_public_key.get_note();
        // Load auth witness and format as an u8 array
        let witness: [Field; 64] = unsafe {
            get_auth_witness(outer_hash)
        };
        let mut signature: [u8; 64] = [0; 64];
        for i in 0..64 {
            signature[i] = witness[i] as u8;
        }
        let mut is_member = false;

        // Verify signature using hardcoded public key
        std::schnorr::verify_signature(
            public_key.x,
            public_key.y,
            signature,
            outer_hash.to_be_bytes::<32>()
        )
    }
}


