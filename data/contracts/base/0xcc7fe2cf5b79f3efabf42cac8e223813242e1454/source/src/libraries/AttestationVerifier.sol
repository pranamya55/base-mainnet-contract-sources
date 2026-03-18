// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// External: EAS
import {Attestation} from "eas-contracts/IEAS.sol";

/// @title EAS Attestation Verifier.
///
/// @dev Helper functions to verify an EAS attestation.
///
/// @author Coinbase
library AttestationVerifier {
    /// @notice Verifies the EAS attestation, ensuring its validity, integrity,
    ///         targeted recipient, and adherence to the expected schema.
    ///
    /// @dev Returns false if the attestation is not found,
    ///      has an unexpected recipient, has an unexpected schema,
    ///      has expired or has been revoked.
    ///
    /// @param attestation Full EAS attestation to verify.
    /// @param recipient Address of the expected attestation's subject.
    /// @param schemaUid Unique identifier of the expected schema.
    ///
    /// @return A boolean indicating if the attestation is valid.
    function verifyAttestation(Attestation memory attestation, address recipient, bytes32 schemaUid)
        internal
        view
        returns (bool)
    {
        // Attestation must exist.
        if (attestation.uid == 0) {
            return false;
        }
        // Attestation being checked must be for the expected recipient.
        if (attestation.recipient != recipient) {
            return false;
        }
        // Attestation being checked must be using the expected schema.
        if (attestation.schema != schemaUid) {
            return false;
        }
        // Attestation must not be expired.
        if (attestation.expirationTime != 0 && attestation.expirationTime <= block.timestamp) {
            return false;
        }
        // Attestation must not be revoked.
        if (attestation.revocationTime != 0) {
            return false;
        }
        // EAS sets the attester address when the attestation is made
        if (attestation.attester == address(0)) {
            return false;
        }
        // Guards against misconfigured schema
        if (attestation.schema == 0) {
            return false;
        }

        return true;
    }
}
