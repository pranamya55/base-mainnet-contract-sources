// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {CollectionCreationRequest} from "../interfaces/ISharedConstructs.sol";
import "../interfaces/IErrors.sol";
import {IMintFactory, IMint, Royalty, MintingFee} from "../interfaces/IMintFactory.sol";
import {MintUtil} from "../../utils/MintUtil.sol";

/*

   ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗███████╗ ██████╗ ██████╗  ██████╗ ███████╗
   ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
      ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║  ███╗█████╗
      ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
      ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
      ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
*/
/// @title Open Edition 721 NFT Collection
/// @dev NFT Collection which supports an Open Edition style with shared metadata between all tokens.
/// @author Coinbase - @polak.eth
contract OpenEdition721Mint is
    IMint,
    ERC721("", ""),
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @dev Current Token Id matches the token id type of Solmate
    uint256 public currentTokenId;

    /// @dev Metadata for the minting contract
    CollectionCreationRequest public metadata;

    /// @dev Mint Factory reference for fees
    address public mintingContract;

    /// @dev MintConfigChanged is required for Reservoir Minting ingestion
    /// @notice See Reference: https://github.com/reservoirprotocol/indexer/tree/main/packages/mint-interface
    event MintConfigChanged();

    /// @dev Withdrawn is emitted if an owner has withdrawn an accidental funds transfer to the contract.
    event Withdrawn(address indexed owner, uint256 amount);

    /// @dev CommentEvent is emitted when a creator or minter attaches a comment with their mint.
    event TokenForgeMintComment(address indexed to, uint256 quantity, string comment);

    /// @dev Event emitted when a token forge mint occurs
    event TokenForgeMint(address indexed to, uint256 quantity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // disabled initializers so they cannot be called again.
    }

    /// @dev Initializer which creates a new NFT collection based on the request.
    /// @notice This is Initializable because we are using clones to create.
    function initialize(CollectionCreationRequest memory request, address mintingContract_) public initializer {
        if (mintingContract_ == address(0)) {
            revert IErrors.InvalidContractAddress();
        }

        // Make sure the creator gets ownership of the contract
        __Ownable2Step_init();
        _transferOwnership(request.creator);

        __ReentrancyGuard_init();

        // Set super params
        name = request.name;
        symbol = request.symbol;

        // Contract Params
        _setMetadata(request);
        metadata.mintType = request.mintType; //Only allowed to set on init
        mintingContract = mintingContract_;
        currentTokenId = 1; // Set current to 1 so the first NFT is #1 and not #0
        emit MintConfigChanged();
    }

    /**
     * ------------ External ------------
     */
    // @dev standard mint function
    function mint(address to, uint256 quantity) external payable nonReentrant {
        if (quantity == 0) {
            revert IErrors.InvalidMintQuantity();
        }

        // Check we don't exceed max supply, add one since we start at tokenId = 1.
        if (currentTokenId + quantity > metadata.maxSupply + 1) {
            revert IErrors.OutOfSupply();
        }

        // Check the mint has started or ended.
        if (metadata.startTime > 0 && metadata.startTime > block.timestamp) {
            revert IErrors.MintingNotStarted();
        }

        if (metadata.endTime > 0 && metadata.endTime < block.timestamp) {
            revert IErrors.MintingClosed();
        }

        // Check if we are over wallet limits
        if (balanceOf(to) + quantity > metadata.maxPerWallet) {
            revert IErrors.OverClaimLimit();
        }

        // Check the correct amount of ETH sent.
        uint256 creatorFee;
        uint256 platformFee;
        address platformFeeAddr;
        (creatorFee, platformFee, platformFeeAddr) = _getFees(quantity);

        // Verify the exact amount, don't want to deal with refunding ETH.
        if (msg.value != creatorFee + platformFee) {
            revert IErrors.IncorrectETHAmount(msg.value, creatorFee + platformFee);
        }

        // Increment OE
        for (uint64 i = 0; i < quantity; i++) {
            _safeMint(to, currentTokenId++);
        }
        uint256 paid = 0;
        paid += platformFee;

        // Pay Platform Fee
        (bool payPlatformFee,) = platformFeeAddr.call{value: platformFee}("");
        if (!payPlatformFee) {
            revert IErrors.FailedToSendEth();
        }

        // Pay Creator Royalties
        for (uint256 i = 0; i < metadata.royalties.length; i++) {
            Royalty memory royalty = metadata.royalties[i];
            uint256 royaltyAmount = quantity * royalty.amt;
            paid += royaltyAmount;
            (bool payRoyaltyResult,) = royalty.to.call{value: royaltyAmount}("");
            if (!payRoyaltyResult) {
                revert IErrors.FailedToSendEth();
            }
        }

        if (paid != creatorFee + platformFee) {
            revert IErrors.IncorrectETHAmount(paid, creatorFee + platformFee);
        }

        emit TokenForgeMint(to, quantity);
    }

    function mintWithComment(address to, uint256 quantity, string calldata comment) external payable {
        this.mint{value: msg.value}(to, quantity);
        if (bytes(comment).length > 0) {
            emit TokenForgeMintComment(to, quantity, comment);
        }
    }

    /// @dev Allows an owner to extract a eth balance from the contract.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool payOwnerResult,) = owner().call{value: balance}("");
        if (!payOwnerResult) {
            revert IErrors.FailedToSendEth();
        }
        emit Withdrawn(owner(), balance);
    }

    /// @dev Allows an owner to update the metadata of the collection.
    /// @notice This will allow and owner to change claim conditions owners should burn collections that should not change.

    function setMetadata(CollectionCreationRequest memory metadata_) external onlyOwner {
        _setMetadata(metadata_);
        emit MintConfigChanged();
    }

    function contractURI() external view returns (string memory) {
        uint256 creatorFee;
        uint256 platformFee;
        (creatorFee, platformFee,) = _getFees(1);
        return MintUtil.contractURI(metadata, creatorFee + platformFee, true);
    }

    /// @dev get the total minted quantity.
    /// @notice have to offset because we are starting at #1 vs #0
    function totalSupply() external view returns (uint256) {
        return currentTokenId - 1;
    }

    /**
     * ------------ Public ------------
     */
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        if (tokenId > currentTokenId || tokenId == 0) {
            revert IErrors.TokenDoesNotExist({tokenId: tokenId});
        }
        return MintUtil.getOpenEditionUri(metadata, tokenId, true);
    }

    function getMetadata() public view returns (CollectionCreationRequest memory) {
        return metadata;
    }

    /// @dev Gets the total cost to mint this collection.
    /// @notice We call the mint factory to determine platform costs.
    function cost(uint256 quantity) public view returns (uint256) {
        uint256 creatorFee;
        uint256 platformFee;
        (creatorFee, platformFee,) = _getFees(quantity);
        return creatorFee + platformFee;
    }

    /**
     *  ------------ Internal ------------
     */
    /// @dev Gets the fees for this collection.
    /// @notice We call the mint factory to determine platform costs.
    function _getFees(uint256 quantity) internal view returns (uint256, uint256, address) {
        IMintFactory mintFactory = IMintFactory(mintingContract);
        MintingFee memory mintingFee = mintFactory.getMintingFee(address(this));
        uint256 creatorFee = (metadata.cost * quantity);
        uint256 platformFee = mintingFee.fee * quantity;
        return (creatorFee, platformFee, mintingFee.addr);
    }

    function _setMetadata(CollectionCreationRequest memory metadata_) internal {
        MintUtil.validateCollectionCreationRequest(metadata_);

        // Manually copy simple fields
        metadata.creator = metadata_.creator;
        metadata.name = metadata_.name;
        metadata.description = metadata_.description;
        metadata.symbol = metadata_.symbol;
        metadata.image = metadata_.image;
        metadata.animation_url = metadata_.animation_url;
        metadata.maxSupply = metadata_.maxSupply;
        metadata.maxPerWallet = metadata_.maxPerWallet;
        metadata.cost = metadata_.cost;
        metadata.startTime = metadata_.startTime;
        metadata.endTime = metadata_.endTime;

        // Make sure to remove old royalties
        delete metadata.royalties;
        // Manually copy array fields
        for (uint256 i = 0; i < metadata_.royalties.length; i++) {
            metadata.royalties.push(Royalty({to: metadata_.royalties[i].to, amt: metadata_.royalties[i].amt}));
        }
    }
}
