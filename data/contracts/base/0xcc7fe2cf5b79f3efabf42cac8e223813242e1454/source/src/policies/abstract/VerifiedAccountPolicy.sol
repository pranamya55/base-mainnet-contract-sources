// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// External: EAS
import {Attestation} from "eas-contracts/IEAS.sol";

// Internal
import {AttestationFinder} from "./AttestationFinder.sol";
import {AttestationVerifier} from "../../libraries/AttestationVerifier.sol";
import {InvalidSchema} from "./PolicyErrors.sol";
import {PolicyVerifier} from "./PolicyVerifier.sol";

/// @title VerifiedAccountPolicy contract.
///
/// @notice Policy contract to verify if the caller has a valid VerifiedAccount (VA)
///         or VerifiedBusinessAccount (VBA) attestation.
///
/// @dev This contract is a base contract for other policies to inherit from.
/// @dev It relies on the `EAS` contract and an `AttestationFinder` to retrieve
///      VA and VBA attestations issued to the address. It also relies on the
///      `AttestationVerifier` library to validate the attestations. Therefore,
///      as long as the address has a valid VA or VBA attestation, the verification
///      should pass.
///
/// @author Coinbase
abstract contract VerifiedAccountPolicy is AttestationFinder, PolicyVerifier {
    /// @notice Uid of the VerifiedAccount (VA) schema.
    bytes32 internal _vaSchemaUid;
    /// @notice Uid of the VerifiedBusinessAccount (VBA) schema.
    bytes32 internal _vbaSchemaUid;

    /// @notice Emitted when the uid of VerifiedAccount (VA) schema is updated.
    ///
    /// @param previousSchema Uid of the previous VA schema.
    /// @param currentSchema Uid of the new VA schema.
    event VASchemaUpdated(bytes32 previousSchema, bytes32 currentSchema);
    /// @notice Emitted when the uid of VerifiedBusinessAccount (VBA) schema is updated.
    ///
    /// @param previousSchema Uid of the previous VBA schema.
    /// @param currentSchema Uid of the new VBA schema.
    event VBASchemaUpdated(bytes32 previousSchema, bytes32 currentSchema);

    /// @param vaSchemaUid Uid of the VerifiedAccount (VA) schema.
    /// @param vbaSchemaUid Uid of the VerifiedBusinessAccount (VBA) schema.
    constructor(bytes32 vaSchemaUid, bytes32 vbaSchemaUid) {
        _setVASchema(vaSchemaUid);
        _setVBASchema(vbaSchemaUid);
    }

    /// @notice Get the schema uid of VerifiedAccount (VA).
    function getVASchema() external view returns (bytes32) {
        return _vaSchemaUid;
    }

    /// @notice Get the schema uid of VerifiedBusinessAccount (VBA).
    function getVBASchema() external view returns (bytes32) {
        return _vbaSchemaUid;
    }

    /// @inheritdoc PolicyVerifier
    ///
    /// @notice Verifies whether the sender address has a valid VerifiedAccount (VA) or VerifiedBusinessAccount (VBA)
    ///			attestation.
    function _verify(address sender, bytes calldata) internal view virtual override returns (bool) {
        Attestation memory vaAttestation = _findAttestation(sender, _vaSchemaUid);

        if (vaAttestation.uid != 0 && AttestationVerifier.verifyAttestation(vaAttestation, sender, _vaSchemaUid)) {
            return true;
        }

        Attestation memory vbaAttestation = _findAttestation(sender, _vbaSchemaUid);
        if (vbaAttestation.uid != 0) {
            return AttestationVerifier.verifyAttestation(vbaAttestation, sender, _vbaSchemaUid);
        }
        return false;
    }

    /// @dev Sets the uid of VerifiedAccount (VA) schema
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {VASchemaUpdated} event.
    ///
    /// @param schemaUid Uid of the new VA schema.
    function _setVASchema(bytes32 schemaUid) internal {
        if (schemaUid == 0) {
            revert InvalidSchema();
        }
        if (schemaUid == _vaSchemaUid) {
            return;
        }

        bytes32 previousSchema = _vaSchemaUid;
        _vaSchemaUid = schemaUid;
        emit VASchemaUpdated(previousSchema, schemaUid);
    }

    /// @dev Sets the uid of VerifiedBusinessAccount (VBA) schema
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {VBASchemaUpdated} event.
    ///
    /// @param schemaUid Uid of the new VBA schema.
    function _setVBASchema(bytes32 schemaUid) internal {
        if (schemaUid == 0) {
            revert InvalidSchema();
        }
        if (schemaUid == _vbaSchemaUid) {
            return;
        }

        bytes32 previousSchema = _vbaSchemaUid;
        _vbaSchemaUid = schemaUid;
        emit VBASchemaUpdated(previousSchema, schemaUid);
    }
}
