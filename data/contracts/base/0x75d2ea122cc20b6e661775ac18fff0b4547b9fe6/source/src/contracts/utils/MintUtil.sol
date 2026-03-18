// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "../tokenforge/interfaces/ISharedConstructs.sol";
import "./Json.sol";
import {Solarray} from "solarray/Solarray.sol";

/// @title Generic Mint utility for common uses across many different mint types.
/// @author polak.eth
library MintUtil {
    error InvalidCollectionRequest(string message);

    function contractURI(CollectionCreationRequest memory metadata, uint256 cost, bool encode)
        internal
        pure
        returns (string memory)
    {
        string memory jsonMetadata = Json.objectOf(
            Solarray.strings(
                Json.property("name", metadata.name),
                Json.property("description", metadata.description),
                Json.property("symbol", metadata.symbol),
                Json.property("image", metadata.image),
                Json.property("animation_url", metadata.animation_url),
                Json.rawProperty("mintConfig", _mintConfig(metadata, cost))
            )
        );

        if (encode) {
            return encodeJsonToBase64(jsonMetadata);
        } else {
            return jsonMetadata;
        }
    }

    /// @dev MintConfig as defined by Reservoirs standard
    /// @notice See Reference: https://github.com/reservoirprotocol/indexer/tree/main/packages/mint-interface
    function _mintConfig(CollectionCreationRequest memory metadata, uint256 cost)
        internal
        pure
        returns (string memory)
    {
        // Construct the mintConfig JSON
        return Json.objectOf(
            Solarray.strings(
                Json.property("maxSupply", Strings.toString(metadata.maxSupply)),
                Json.rawProperty("phases", Json.array(_encodePhases(metadata, cost)))
            )
        );
    }

    /// @dev Formats for an OpenEdition which is an auto-incrementing name (e.g. NFT #1, NFT #2 ...).
    function getOpenEditionUri(CollectionCreationRequest memory metadata, uint256 tokenId, bool encode)
        internal
        pure
        returns (string memory)
    {
        // Generates a name with edition .. e.g. NFT => NFT #1029
        string memory nameWithTokenId = string(abi.encodePacked(metadata.name, " #", Strings.toString(tokenId)));

        string memory jsonMetadata = Json.objectOf(
            Solarray.strings(
                Json.property("name", nameWithTokenId),
                Json.property("description", metadata.description),
                Json.property("symbol", metadata.symbol),
                Json.property("image", metadata.image),
                Json.property("animation_url", metadata.animation_url)
            )
        );

        if (encode) {
            return encodeJsonToBase64(jsonMetadata);
        } else {
            return jsonMetadata;
        }
    }

    /// @dev Phases are required for the Reservoir minting integration.  Reservoir will read this configuration
    ///      from the ContractURI() function.
    function _encodePhases(CollectionCreationRequest memory metadata, uint256 cost)
        internal
        pure
        returns (string memory)
    {
        string memory maxPerWalletStr = Strings.toString(metadata.maxPerWallet);
        string memory addrParam = '{"name": "recipient","abiType": "address","kind": "RECIPIENT"}';
        string memory qtyParam = '{"name": "quantity", "abiType": "uint256", "kind": "QUANTITY"}';

        // Params used to call the mint function
        string memory params = string(abi.encodePacked(addrParam, ",", qtyParam));

        // Define the method that needs to be called
        string memory txnData = Json.objectOf(
            Solarray.strings(Json.property("method", "0x40c10f19"), Json.rawProperty("params", Json.array(params)))
        );

        // Mint phases (we only support one phase right now)
        return Json.objectOf(
            Solarray.strings(
                Json.property("maxMintsPerWallet", maxPerWalletStr),
                Json.property("startTime", Strings.toString(metadata.startTime)),
                Json.property("endTime", Strings.toString(metadata.endTime)),
                Json.property("price", Strings.toString(cost)),
                Json.rawProperty("tx", txnData)
            )
        );
    }

    function encodeJsonToBase64(string memory str) internal pure returns (string memory) {
        return string.concat("data:application/json;base64,", Base64.encode(abi.encodePacked(str)));
    }

    /// @dev Validates the CollectionCreationRequest for common logical errors.
    /// @param metadata The collection creation request to validate.
    function validateCollectionCreationRequest(CollectionCreationRequest memory metadata) internal pure {
        // Check start and end times
        if (metadata.startTime > metadata.endTime && metadata.endTime != 0) {
            revert InvalidCollectionRequest("End time must be greater than or equal to start time.");
        }

        // Check that royalty amounts add up to mint cost.
        uint256 totalAmt = 0;
        for (uint256 i = 0; i < metadata.royalties.length; i++) {
            if (metadata.royalties[i].to == address(0)) {
                revert InvalidCollectionRequest("Invalid Address");
            }
            totalAmt += metadata.royalties[i].amt;
        }
        if (totalAmt != metadata.cost) {
            revert InvalidCollectionRequest("Total royalties must equal cost");
        }

        if (metadata.royalties.length > 5) {
            revert InvalidCollectionRequest("Cannot have more than 5 royalty addresses");
        }

        // Check for valid max supply and per wallet limits
        if (metadata.maxSupply == 0) {
            revert InvalidCollectionRequest("Max supply must be greater than zero.");
        }
        if (metadata.maxPerWallet == 0) {
            revert InvalidCollectionRequest("Max per wallet must be greater than zero.");
        }

        // Check for non-empty essential strings
        if (isEmptyString(metadata.name) || isEmptyString(metadata.symbol)) {
            revert InvalidCollectionRequest("Name & symbol cannot be empty.");
        }

        if (isEmptyString(metadata.image) && isEmptyString(metadata.animation_url)) {
            revert InvalidCollectionRequest("Must have an image or animation_url.");
        }
    }

    /// @dev Helper function to check if a string is empty.
    /// @param value The string to check.
    /// @return bool Whether the string is empty.
    function isEmptyString(string memory value) internal pure returns (bool) {
        return bytes(value).length == 0;
    }
}
