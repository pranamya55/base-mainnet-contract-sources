// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// External: EAS
import {Attestation} from "eas-contracts/IEAS.sol";

// Internal
import {AttestationFinder} from "./AttestationFinder.sol";
import {AttestationVerifier} from "../../libraries/AttestationVerifier.sol";
import {InvalidSchema} from "./PolicyErrors.sol";
import {PolicyVerifier} from "./PolicyVerifier.sol";

/// @title VerifiedCountryPolicy contract.
///
/// @notice Policy contract to verify if the caller in a verified country.
///
/// @dev This contract is a base contract for other policies to inherit from.
/// @dev It relies on the `EAS` contract and an `AttestationFinder` to retrieve
///      VC and VBC attestations issued to the address. It also relies on the
///      `AttestationVerifier` library to validate of the attestations.
/// @dev Once retrieved, the policy will decode the attestation data to get the
///      country code and check if the country code is in the list of verified
///      countries.
///
/// @author Coinbase
abstract contract VerifiedCountryPolicy is AttestationFinder, PolicyVerifier {
    /// @notice Uid of the VerifiedCountry (VC) schema
    bytes32 internal _vcSchemaUid;
    /// @notice Uid of the VerifiedBusinessCountry (VBC) schema
    bytes32 internal _vbcSchemaUid;
    /// @notice List of verified countries
    mapping(string countryCode => bool allowed) private _countries;

    /// @notice Emitted when the uid of VerifiedCountry (VC) schema is updated
    ///
    /// @param previousSchema Uid of the previous VC schema.
    /// @param currentSchema Uid of the new VC schema.
    event VCSchemaUpdated(bytes32 previousSchema, bytes32 currentSchema);
    /// @notice Emitted when the uid of VerifiedBusinessCountry (VBC) schema is updated
    ///
    /// @param previousSchema Uid of the previous VBC schema.
    /// @param currentSchema Uid of the new VBC schema.
    event VBCSchemaUpdated(bytes32 previousSchema, bytes32 currentSchema);
    /// @notice Emitted when a country is added to the list of verified countries
    ///
    /// @param countryCode The country code added.
    event CountryAdded(string countryCode);
    /// @notice Emitted when a country is removed from the list of verified countries
    ///
    /// @param countryCode The country code removed.
    event CountryRemoved(string countryCode);

    /// @notice Error when no attestation is found
    error VerifiedCountryAttestationNotFound();
    /// @notice Error when both attestations are valid
    error InvalidVerifiedCountryAttestation();
    /// @notice Country code is not valid.
    error InvalidCountryCode();

    /// @param vcSchemaUid Uid of the VerifiedCountry (VC) schema.
    /// @param vbcSchemaUid Uid of the VerifiedBusinessCountry (VBC) schema.
    constructor(bytes32 vcSchemaUid, bytes32 vbcSchemaUid) {
        _setVCSchema(vcSchemaUid);
        _setVBCSchema(vbcSchemaUid);
    }

    /// @notice Get the uid of VerifiedCountry (VC) schema.
    ///
    /// @return The uid of the VC schema.
    function getVCSchema() external view returns (bytes32) {
        return _vcSchemaUid;
    }

    /// @notice Get the uid of VerifiedBusinessCountry (VBC) schema
    ///
    /// @return The uid of the VBC schema
    function getVBCSchema() external view returns (bytes32) {
        return _vbcSchemaUid;
    }

    /// @notice Check if the country code is in the list of verified countries.
    ///
    /// @param countryCode The country code to be checked.
    ///
    /// @return A boolean indicating if the country code is in the list of verified countries.
    function isVerifiedCountry(string memory countryCode) external view returns (bool) {
        return _isVerifiedCountry(countryCode);
    }

    /// @inheritdoc PolicyVerifier
    ///
    /// @notice Verifies whether the sender address has a valid VerifiedCountry (VC) or VerifiedBusinessCountry (VBC)
    ///			attestation, and the country code is in the list of verified countries.
    function _verify(address sender, bytes calldata) internal view virtual override returns (bool) {
        Attestation memory vcAttestation = _findAttestation(sender, _vcSchemaUid);
        if (
            vcAttestation.uid != 0 && AttestationVerifier.verifyAttestation(vcAttestation, sender, _vcSchemaUid)
                && _isVerifiedCountry(_decodeCountryCode(vcAttestation.data))
        ) {
            return true;
        }

        Attestation memory vbcAttestation = _findAttestation(sender, _vbcSchemaUid);
        if (vbcAttestation.uid != 0 && AttestationVerifier.verifyAttestation(vbcAttestation, sender, _vbcSchemaUid)) {
            return _isVerifiedCountry(_decodeCountryCode(vbcAttestation.data));
        }

        return false;
    }

    /// @dev Sets the uid of VerifiedCountry (VC) schema
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {VCSchemaUpdated} event.
    ///
    /// @param schemaUid Uid of the new VC schema.
    function _setVCSchema(bytes32 schemaUid) internal {
        if (schemaUid == 0) {
            revert InvalidSchema();
        }
        if (schemaUid == _vcSchemaUid) {
            return;
        }

        bytes32 previousSchema = _vcSchemaUid;
        _vcSchemaUid = schemaUid;
        emit VCSchemaUpdated(previousSchema, schemaUid);
    }

    /// @dev Sets the uid of VerifiedBusinessCountry (VBC) schema
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {VBCSchemaUpdated} event.
    ///
    /// @param schemaUid Uid of the new VBC schema.
    function _setVBCSchema(bytes32 schemaUid) internal {
        if (schemaUid == 0) {
            revert InvalidSchema();
        }
        if (schemaUid == _vbcSchemaUid) {
            return;
        }

        bytes32 previousSchema = _vbcSchemaUid;
        _vbcSchemaUid = schemaUid;
        emit VBCSchemaUpdated(previousSchema, schemaUid);
    }

    /// @dev Adds a country to the list of verified countries.
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {CountryAdded} event.
    /// @dev The function reverts if an invalid country is specified.
    ///
    /// @param countryCode The country code to be added.
    function _addCountry(string memory countryCode) internal {
        if (!_validCountry(countryCode)) {
            revert InvalidCountryCode();
        }
        if (_countries[countryCode]) {
            return;
        }

        _countries[countryCode] = true;
        emit CountryAdded(countryCode);
    }

    /// @dev Removes a country from the list of verified countries.
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {CountryRemoved} event.
    /// @dev The function reverts if an invalid country is specified.
    ///
    /// @param countryCode The country code to be removed.
    function _removeCountry(string memory countryCode) internal {
        if (!_validCountry(countryCode)) {
            revert InvalidCountryCode();
        }
        if (!_countries[countryCode]) {
            return;
        }

        _countries[countryCode] = false;
        emit CountryRemoved(countryCode);
    }

    /// @dev Checks if the country code complies with the Alpha-2 standard.
    ///
    /// @param countryCode The country code to be checked.
    ///
    /// @return A boolean indicating if the country code is valid.
    function _validCountry(string memory countryCode) private pure returns (bool) {
        // checking byte length is sufficient as valid Alpha-2 consists of two (single-byte) ASCII characters
        return bytes(countryCode).length == 2;
    }

    /// @dev Check if the country code is in the list of verified countries.
    ///
    /// @param countryCode The country code to be checked.
    ///
    /// @return A boolean indicating if the country code is in the list of verified countries.
    function _isVerifiedCountry(string memory countryCode) private view returns (bool) {
        return _countries[countryCode];
    }

    /// @dev Decodes the country code from the attestation data.
    ///
    /// @param attestationData The attestation data to be decoded.
    ///
    /// @return The decoded country code string.
    function _decodeCountryCode(bytes memory attestationData) private pure returns (string memory) {
        // The Verified Country attestation schema is 'string verifiedCountry'.
        // String fields are abi encoded by 3 uint256 values.
        // The 1st uint256, uint256(32), is the offset of when the string starts, which is after 32 bytes.
        // The 2nd unint256, uint256(2), is the length of the string, which is always 2 since we use alpha2 numeric country codes
        // The 3rd uint256, uint16(country) + uint240(0), is the 2 byte ascii encoded country code followed by 30 bytes of padding
        (, uint256 b, uint256 c) = abi.decode(attestationData, (uint256, uint256, uint256));
        uint16 country = uint16(c >> 256 - b * 8);
        return string(abi.encodePacked(country));
    }
}
