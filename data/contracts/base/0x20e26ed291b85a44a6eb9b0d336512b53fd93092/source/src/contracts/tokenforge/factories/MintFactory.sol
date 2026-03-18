// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../mint-contracts/OpenEdition721Mint.sol";
import {CollectionCreationRequest} from "../interfaces/ISharedConstructs.sol";
import {MintUtil} from "../../utils/MintUtil.sol";
import "../interfaces/IErrors.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/*

   ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗███████╗ ██████╗ ██████╗  ██████╗ ███████╗
   ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
      ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║  ███╗█████╗
      ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
      ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
      ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
*/
/// @title Generic Mint Factory which will be used to create premint NFT contracts as cheap as possible.
/// @author Coinbase - @polak.eth
contract MintFactory is IMintFactory, Pausable, Ownable2Step, ReentrancyGuard {
    /// @dev Store a mapping from sig -> address to prevent duplicates / collisions
    mapping(address => bool) public contracts;

    /// @dev Allow a creator to cancel their signature.
    mapping(bytes => bool) public cancelledSignatures;

    /// @dev Track which signatures have been used.
    mapping(bytes => bool) public usedSignatures;

    /// @dev The default minting fee if there is not an override in feeOverride
    MintingFee public mintingFee;

    /// @dev Fee overrides so we can change either the amount or destination of the fees.
    mapping(address => MintingFee) public feeOverrides;

    /// @dev Mapping of our mint implementations ready to be cloned.
    mapping(string => address) public mintImplementation;

    /// @dev EIP-712 Domain definition
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev EIP-712 CollectionCreation request type
    bytes32 constant COLLECTION_CREATION_REQUEST_TYPEHASH = keccak256(
        "CollectionCreationRequest(address creator,string name,string description,string symbol,string image,string animation_url,string mintType,uint128 maxSupply,uint128 maxPerWallet,uint256 cost,uint256 startTime,uint256 endTime,Royalty[] royalties,uint256 nonce)Royalty(address to,uint256 amt)"
    );

    bytes32 constant ROYALTIES_REQUEST_TYPEHASH = keccak256("Royalty(address to,uint256 amt)");

    /// @dev EIP-712 Domain Separator, initialized in the constructor.
    bytes32 public immutable domainSeparator;

    /// @dev Event That is Emitted when a contract is created
    event ContractCreated(address indexed contractAddress, address indexed minter);
    event SignatureInvalidated(bytes indexed signature, address indexed minter);

    /// @dev Default constructor which takes an owner and a location for platform royalties to be sent.
    constructor(address initialOwner, address platformFeeAddress) Ownable(initialOwner) {
        domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("MintFactory")), // Name
                keccak256(bytes("1")), // Version
                block.chainid,
                address(this)
            )
        );

        // Set default fee of 0.0001 eth / mint & 0.00005 referral fee
        MintingFee memory fee =
            MintingFee({hasOverride: false, addr: platformFeeAddress, fee: 0.0001 ether, referral: 0.00005 ether});
        _setMintingFee(fee);

        // Default contracts
        mintImplementation["OPEN_EDITION_721"] = address(new OpenEdition721Mint());
    }

    /**
     * ------------ External ------------
     */

    /// @dev Creates a new collection based on the Creators initial vision.  Leverages signature validation
    ///      to ensure a collection can only be created in the same shape as the creators minting signature.
    function createCollection(
        CollectionCreationRequest calldata request,
        bytes memory signature,
        uint256 mintQuantity,
        string calldata comment,
        address referral
    ) external payable nonReentrant whenNotPaused returns (address) {
        // Check if the contract is already deployed and call mint
        if (contracts[getMintingAddress(request)]) {
            address existingMintAddr = getMintingAddress(request);
            IMint existingMint = IMint(existingMintAddr);
            existingMint.mintWithComment{value: msg.value}(msg.sender, mintQuantity, comment, referral);
            return existingMintAddr;
        }

        // Check valid signature
        if (!verifySignature(request, signature)) {
            revert IErrors.InvalidSignature();
        }

        MintUtil.validateCollectionCreationRequest(request);

        // Build and deploy the new Mint Contract
        bytes32 salt = getSalt(request);
        address contractAddr = _getMintImplementationAddr(request.mintType);
        address mintAddress = Clones.cloneDeterministic(contractAddr, salt);

        // Mark the signature + contract as deployed, so it cannot be used again with a new version of the minting contract.
        contracts[mintAddress] = true;
        usedSignatures[signature] = true;

        // Initialize the Mint with the creators specifications
        IMint newMint = IMint(mintAddress);
        newMint.initialize(request, address(this));

        if (mintQuantity > 0) {
            // Mint will confirm the sender is only sending the exact ETH amount
            newMint.mintWithComment{value: msg.value}(msg.sender, mintQuantity, comment, referral);
        }

        // Emit contract creation
        emit ContractCreated(mintAddress, msg.sender);

        return mintAddress;
    }

    /// @dev Allows a creator to cancel a signature if they do not want a collection to be minted.
    /// @param signature The signature to be cancelled
    function cancelSignature(CollectionCreationRequest calldata request, bytes calldata signature) external {
        if (!verifySignature(request, signature)) {
            revert IErrors.InvalidSignature();
        }

        // Ensure the caller is the creator so arbitrary wallets cannot cancel other creators signatures.
        if (request.creator != msg.sender) {
            revert IErrors.NotCollectionCreator();
        }

        // Emit an event which will let our BE know to cancel signatures.
        emit SignatureInvalidated(signature, msg.sender);

        cancelledSignatures[signature] = true;
    }

    /// @dev support a mint function at the Factory layer as a convenience.
    /// @param contractAddress The address of the contract you want to mint.
    /// @param to The address the mint should be sent to.
    /// @param quantity of NFTs you want to mint.
    function mint(address contractAddress, address to, uint256 quantity, string calldata comment, address referral)
        external
        payable
    {
        // Only allow minting from contracts we have deployed
        if (!contracts[contractAddress]) {
            revert IErrors.InvalidContractAddress();
        }

        IMint newMint = IMint(contractAddress);
        newMint.mintWithComment{value: msg.value}(to, quantity, comment, referral);
    }

    /// @dev Get the minting fee for a collection, will return an override or the default.
    /// @notice This will return a default fee if not overridden.
    /// @param contractAddress you want to get a fee for.
    function getMintingFee(address contractAddress) external view returns (MintingFee memory) {
        MintingFee memory feeOverride = feeOverrides[contractAddress];
        if (feeOverride.hasOverride) {
            return feeOverride;
        }

        // Use default fee
        return mintingFee;
    }

    /**
     * ------------ OnlyOwner ------------
     */
    /// @dev Allows an owner to set the minting contract for an given type.  This will both new contracts
    ///      & upgrades to existing mint types.
    function setMintContract(string calldata contractType, address addr) external onlyOwner {
        mintImplementation[contractType] = address(addr);
    }

    /// @dev Allows an Owner to update the default minting fee for all contracts.
    function setMintingFee(MintingFee memory fee) public onlyOwner {
        _verifyFee(fee);
        mintingFee = fee;
    }

    /// @dev Allows an owner to override the fee for a specific contract address
    function setMintingFeeOverride(address addr, MintingFee memory fee) external onlyOwner {
        _verifyFee(fee);
        feeOverrides[addr] = fee;
    }

    /// @dev Allows an owner to pause a contract.
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /// @dev Allows an owner to unpause a paused contract.
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /**
     * ------------ Public ------------
     */
    ///@dev Helper method to get the bytes needed to be signed for an account to create a free mint.  This implements
    ///      EIP-712 signatures so a creator can see exactly what their signing.
    ///@param request Collection creation request
    function getBytesToSign(CollectionCreationRequest memory request) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, getItemHash(request)));
    }

    ///@dev Helped function for hashing the creation struct.  Leaving as public as I could see some value for
    ///     the frontend to call.
    function getItemHash(CollectionCreationRequest memory request) public pure returns (bytes32) {
        bytes32[] memory royaltyHashes = new bytes32[](request.royalties.length);
        for (uint256 i = 0; i < request.royalties.length; i++) {
            royaltyHashes[i] =
                keccak256(abi.encode(ROYALTIES_REQUEST_TYPEHASH, request.royalties[i].to, request.royalties[i].amt));
        }

        // Needed to break up the hash into two parts to avoid nested depth issues (no IR plz)
        bytes memory pt1 = abi.encode(
            COLLECTION_CREATION_REQUEST_TYPEHASH,
            request.creator,
            keccak256(bytes(request.name)),
            keccak256(bytes(request.description)),
            keccak256(bytes(request.symbol)),
            keccak256(bytes(request.image)),
            keccak256(bytes(request.animation_url)),
            keccak256(bytes(request.mintType))
        );
        return keccak256(
            abi.encodePacked(
                pt1,
                abi.encode(
                    request.maxSupply,
                    request.maxPerWallet,
                    request.cost,
                    request.startTime,
                    request.endTime,
                    keccak256(abi.encodePacked(royaltyHashes)),
                    request.nonce
                )
            )
        );
    }

    /// @dev Gets the predicted minting address for a creation payload.
    function getMintingAddress(CollectionCreationRequest memory request) public view returns (address) {
        bytes32 salt = getSalt(request);
        address implementation = _getMintImplementationAddr(request.mintType);
        return Clones.predictDeterministicAddress(implementation, salt, address(this));
    }

    /// @dev Verifies a signature is valid, implements EIP-712
    /// @notice There is a reentrancy risk with isValidSignatureNow as it makes external calls for smart contracts.
    function verifySignature(CollectionCreationRequest memory request, bytes memory signature)
        public
        view
        returns (bool)
    {
        // Check if the signature was invalidated.
        if (cancelledSignatures[signature]) {
            revert IErrors.SignatureInvalidated();
        }

        // Check if the signature was already used.
        if (usedSignatures[signature]) {
            revert IErrors.SignatureUsed();
        }

        bytes32 digest = getBytesToSign(request);
        return SignatureChecker.isValidSignatureNow(request.creator, digest, signature);
    }

    /// @dev Gets a contract creation salt to ensure contracts are unique based on their request.  There is a
    ///      nonce that is appended to the request to ensure uniqueness.
    function getSalt(CollectionCreationRequest memory request) public view returns (bytes32) {
        // WARNING: Write explicit ordering here and ensure solidity includes all values. This salt needs to be unique
        // otherwise there will be a contract creation collision.
        return keccak256(abi.encode(request, address(this)));
    }

    /**
     *  ------------ Internal ------------
     */
    /// @dev Gets the mint implementation address to be used by Clone
    function _getMintImplementationAddr(string memory mintType) internal view returns (address) {
        address mintImpl = mintImplementation[mintType];
        if (mintImpl == address(0)) {
            revert IErrors.InvalidMintType();
        }
        return mintImpl;
    }

    function _verifyFee(MintingFee memory contractFees) internal pure {
        if (contractFees.referral > contractFees.fee) {
            revert IErrors.InvalidFee();
        }
    }

    function _setMintingFee(MintingFee memory fee) private {
        _verifyFee(fee);
        mintingFee = fee;
    }
}
