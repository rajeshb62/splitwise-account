use dep::aztec::prelude::{AztecAddress, PrivateContext, PrivateSet, NoteGetterOptions};
use dep::aztec::note::note_getter_options::SortOrder;
use dep::aztec::encrypted_logs::encrypted_note_emission::{encode_and_encrypt_note, encode_and_encrypt_note_unconstrained};
use dep::aztec::keys::getters::get_public_keys;
use dep::value_note::{filter::filter_notes_min_sum, value_note::{ValueNote, VALUE_NOTE_LEN}};
use crate::notes::NewAddressNote::NewAddressNote;

pub fn membership_check(creditor: AztecAddress, debtor: AztecAddress, contract_address: AztecAddress, location: PrivateSet<NewAddressNote, &mut PrivateContext>) -> bool {
    let mut creditor_in_group = false;
    let mut debtor_in_group = false;
    let contract_address_keys = get_public_keys(contract_address);
    let options = NoteGetterOptions::new();
    let members_notes: BoundedVec<NewAddressNote, 16> = location.get_notes(options);
    for i in 0..members_notes.max_len() {
        if i < members_notes.len() {
            let note = members_notes.get_unchecked(i);
            if note.address == creditor {
                creditor_in_group = true;
            }
            if note.address == debtor {
                debtor_in_group = true;
            }
        }
    }
    assert(creditor_in_group, "Creditor is not in the group");
    assert(debtor_in_group, "Debtor is not in the group");
    true
}

pub fn increment(
    // docs:start:increment_args
    balance: PrivateSet<ValueNote, &mut PrivateContext>,
    amount: Field,
    recipient: AztecAddress,
    outgoing_viewer: AztecAddress // docs:end:increment_args
) {
    let recipient_keys = get_public_keys(recipient);
    let outgoing_viewer_ovpk_m = get_public_keys(outgoing_viewer).ovpk_m;

    let mut note = ValueNote::new(amount, recipient_keys.npk_m.hash());
    // Insert the new note to the owner's set of notes and emit the log if value is non-zero.
    balance.insert(&mut note).emit(
        encode_and_encrypt_note_unconstrained(
            balance.context,
            outgoing_viewer_ovpk_m,
            recipient_keys.ivpk_m,
            recipient
        )
    );
}

pub fn membership_check_multiple(creditor: AztecAddress, debtors: [AztecAddress; 2], contract_address: AztecAddress, location: PrivateSet<NewAddressNote, &mut PrivateContext>) -> bool {
    membership_check(creditor, debtors[0], contract_address, location) & membership_check(creditor, debtors[1], contract_address, location)
}

pub fn decrement(
    balance: PrivateSet<ValueNote, &mut PrivateContext>,
    amount: Field,
    owner: AztecAddress,
    outgoing_viewer: AztecAddress
) {
    let sum = decrement_by_at_most(balance, amount, owner, outgoing_viewer);
    assert(sum == amount, "Balance too low");
}

// Sort the note values (0th field) in descending order.
// Pick the fewest notes whose sum is equal to or greater than `amount`.
pub fn create_note_getter_options_for_decreasing_balance(amount: Field) -> NoteGetterOptions<ValueNote, VALUE_NOTE_LEN, Field, Field> {
    NoteGetterOptions::with_filter(filter_notes_min_sum, amount).sort(ValueNote::properties().value, SortOrder.DESC)
}


// Similar to `decrement`, except that it doesn't fail if the decremented amount is less than max_amount.
// The motivation behind this function is that there is an upper-bound on the number of notes a function may
// read and nullify. The requested decrementation `amount` might be spread across too many of the `owner`'s
// notes to 'fit' within this upper-bound, so we might have to remove an amount less than `amount`. A common
// pattern is to repeatedly call this function across many function calls, until enough notes have been nullified to
// equal `amount`.
//
// It returns the decremented amount, which should be less than or equal to max_amount.
pub fn decrement_by_at_most(
    balance: PrivateSet<ValueNote, &mut PrivateContext>,
    max_amount: Field,
    owner: AztecAddress,
    outgoing_viewer: AztecAddress
) -> Field {
    let options = create_note_getter_options_for_decreasing_balance(max_amount);
    let notes = balance.pop_notes(options);

    let mut decremented = 0;
    for i in 0..options.limit {
        if i < notes.len() {
            let note = notes.get_unchecked(i);
            decremented += note.value;
        }
    }

    // Add the change value back to the owner's balance.
    let mut change_value = 0;
    if max_amount.lt(decremented) {
        change_value = decremented - max_amount;
        decremented -= change_value;
    }
    increment(balance, change_value, owner, outgoing_viewer);

    decremented
}
