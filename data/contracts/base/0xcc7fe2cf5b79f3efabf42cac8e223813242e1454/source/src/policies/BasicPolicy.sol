// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// External: EAS
import {Attestation} from "eas-contracts/IEAS.sol";
// External: Coinbase Verifications
import {AttestationVerifier} from "coinbase/verifications/libraries/AttestationVerifier.sol";
import {AttestationAccessControl} from "coinbase/verifications/abstracts/AttestationAccessControl.sol";
import {IAttestationIndexer} from "coinbase/verifications/interfaces/IAttestationIndexer.sol";

// Internal
import {BasePolicy} from "./abstract/BasePolicy.sol";
import {ISanctionsList} from "../interfaces/ISanctionsList.sol";
import {IHookPolicy} from "../interfaces/IHookPolicy.sol";
import {NonSanctionedPolicy} from "./abstract/NonSanctionedPolicy.sol";
import {VerifiedAccountPolicy} from "./abstract/VerifiedAccountPolicy.sol";
import {VerifiedCountryPolicy} from "./abstract/VerifiedCountryPolicy.sol";

/// @title BasicPolicy contract.
///
/// @notice A basic policy contract for `Verified Pools` to verify if the sender is allowed
///         to perform an action.
///
/// @dev A composite policy contract that combines a few polcies together to ensure that the caller
///      1) has a verified account
///      2) resides in a verified jurisdiction
///      3) is not sanctioned
///
/// @author Coinbase
contract BasicPolicy is
    VerifiedAccountPolicy,
    VerifiedCountryPolicy,
    NonSanctionedPolicy,
    AttestationAccessControl,
    BasePolicy,
    IHookPolicy
{
    /// @param defaultAdmin The default admin
    /// @param defaultPauser The default pauser
    /// @param vaSchemaUid The schema uid of the VerifiedAccount (VA) schema
    /// @param vbaSchemaUid The schema uid of the VerifiedBusinessAccount (VBA) schema
    /// @param vcSchemaUid The schema uid of the VerifiedCountry (VC) schema
    /// @param vbcSchemaUid The schema uid of the VerifiedBusinessCountry (VBC) schema
    /// @param sanctionsList The `SanctionsList` contract that checks if an address is sanctioned
    /// @param indexer The `AttestationIndexer` contract that indexes interesting attestations
    constructor(
        address defaultAdmin,
        address defaultPauser,
        bytes32 vaSchemaUid,
        bytes32 vbaSchemaUid,
        bytes32 vcSchemaUid,
        bytes32 vbcSchemaUid,
        ISanctionsList sanctionsList,
        IAttestationIndexer indexer
    )
        VerifiedAccountPolicy(vaSchemaUid, vbaSchemaUid)
        VerifiedCountryPolicy(vcSchemaUid, vbcSchemaUid)
        NonSanctionedPolicy(sanctionsList)
        BasePolicy(defaultAdmin, defaultPauser)
    {
        _setIndexer(indexer);
    }

    /// @inheritdoc IHookPolicy
    ///
    /// @notice This function is called by the `Hook` contract to verify if the sender
    ///         is allowed to perform an action.
    function verify(address sender, bytes calldata data) external view override whenNotPaused returns (bool) {
        return _verify(sender, data);
    }

    /// @notice Set the schema uid of VerifiedAccount (VA).
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param schemaUid The uid of the VA schema.
    function setVASchema(bytes32 schemaUid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVASchema(schemaUid);
    }

    /// @notice Set the schema uid of VerifiedBusinessAccount (VBA).
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param schemaUid The uid of the VBA schema.
    function setVBASchema(bytes32 schemaUid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVBASchema(schemaUid);
    }

    /// @notice Set the schema uid of VerifiedCountry (VC).
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param schemaUid The uid of the VC schema.
    function setVCSchema(bytes32 schemaUid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVCSchema(schemaUid);
    }

    /// @notice Set the schema uid of VerifiedBusinessCountry (VBC).
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param schemaUid The uid of the VBC schema.
    function setVBCSchema(bytes32 schemaUid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVBCSchema(schemaUid);
    }

    /// @notice Set the `AttestationIndexer` contract.
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param indexer The address of the `AttestationIndexer' contract
    function setIndexer(IAttestationIndexer indexer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setIndexer(indexer);
    }

    /// @notice Set the `SanctionsList` contract address
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param sanctionsList The address of the `SanctionsList` contract
    function setSanctionsList(ISanctionsList sanctionsList) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setSanctionsList(sanctionsList);
    }

    /// @notice Add a country code to the list of verified countries
    /// @notice This function is only callable by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param countryCode The country code to be added
    function addCountry(string memory countryCode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCountry(countryCode);
    }

    /**
     * @notice Remove a country code from the list of verified countries
     * @param countryCode The country code to be removed
     */
    function removeCountry(string memory countryCode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeCountry(countryCode);
    }

    /// @dev Internal function to find an attestation.
    /// @dev This implements the abstract function in `AttestationFinder`.
    ///      This is needed by the `VerifiedCountryPolicy` and `VerifiedBusinessCountryPolicy`
    ///      to find the attestation for the recipient.
    ///
    /// @param recipient The recipient address to find the attestation for
    /// @param schemaUid The schema uid of the attestation
    ///
    /// @return The EAS attestation
    function _findAttestation(address recipient, bytes32 schemaUid)
        internal
        view
        virtual
        override
        returns (Attestation memory)
    {
        return AttestationAccessControl._getAttestation(recipient, schemaUid);
    }

    /// @dev Verify if the sender address has passed all the policy checks, including:
    ////      1) VerifiedAccountPolicy
    ///       2) VerifiedCountryPolicy
    ///       3) NonSanctionedPolicy
    ///
    /// @param sender The sender address to be verified
    /// @param data Arbitrary data to be passed into the policy
    ///
    /// @return A boolean indicating if the sender is verified
    function _verify(address sender, bytes calldata data)
        internal
        view
        virtual
        override(VerifiedAccountPolicy, VerifiedCountryPolicy, NonSanctionedPolicy)
        returns (bool)
    {
        return VerifiedAccountPolicy._verify(sender, data) && VerifiedCountryPolicy._verify(sender, data)
            && NonSanctionedPolicy._verify(sender, data);
    }
}
