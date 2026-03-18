// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Attestation} from "eas-contracts/IEAS.sol";

/// @title Abstract Contract for Attestation Retrieval.
///
/// @notice This contract provides an abstract interface for retrieving attestations.
///
/// @dev Implements a function to find an attestation by recipient address and schema UID.
///      Derived contracts must implement the _findAttestation function to specify
///      how attestations are retrieved.
///
/// @author Coinbase
abstract contract AttestationFinder {
    /// @notice Retrieves an attestation for a specified recipient and schema.
    ///
    /// @dev This function must be implemented by inheriting contracts to define how
    ///      attestations are searched and retrieved.
    ///
    /// @param recipient The address of the recipient for whom the attestation is intended.
    /// @param schemaUid The unique identifier of the schema used for the attestation.
    ///
    /// @return Attestation Returns an attestation matching the specified recipient and schema.
    function _findAttestation(address recipient, bytes32 schemaUid)
        internal
        view
        virtual
        returns (Attestation memory);
}
